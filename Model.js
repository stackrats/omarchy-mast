// Pure helpers behind the Mast bar widget and its panel: reading the
// `mast status --json` snapshot, deciding what the bar shows, and turning a
// click or a key into an argv vector. Nothing here touches Qt, so the file
// also runs under node for test/model-test.sh.

var STATUSES = ["failed", "degraded", "starting", "running", "stopped"]

// The desktop app registers this scheme (ADR-0010 in the Mast repo): a link
// may select a project or prefill a dialog, never act. A bare link just
// raises the window, which is all "open Mast" needs.
var APP_LINK = "mast://"
var WEBSITE = "https://mast.sh"
var APP_MISSING = "Mast desktop app not found — mast:// links need it. Get it from mast.sh."

function str(value) {
  return value === undefined || value === null ? "" : String(value)
}

function trim(text) {
  return str(text).replace(/^\s+|\s+$/g, "")
}

function clampInt(value, fallback, min, max) {
  var n = parseInt(str(value === undefined || value === null ? fallback : value), 10)
  if (!isFinite(n)) n = fallback
  if (n < min) n = min
  if (n > max) n = max
  return n
}

function emptySnapshot() {
  return {
    ok: false,
    error: "",
    readOnly: false,
    docker: { available: false, reason: "", context: "", error: "" },
    projects: [],
    counts: countProjects([])
  }
}

// ---- Reading the snapshot.

// `mast status --json` prints the engine's snapshot: camelCase keys,
// `protocolVersion` 1, the same document the desktop app reads. Only what
// the widget shows is lifted out, and every field tolerates being absent, so
// an older or newer Mast still yields a picture instead of an exception
// inside a binding.
function parseSnapshot(raw) {
  var text = trim(raw)
  var result = emptySnapshot()
  if (text === "") {
    result.error = "mast printed no status"
    return result
  }
  var snap
  try {
    snap = JSON.parse(text)
  } catch (e) {
    result.error = "mast status output is not JSON"
    return result
  }
  if (!snap || typeof snap !== "object" || Array.isArray(snap)) {
    result.error = "mast status output is not an object"
    return result
  }

  var docker = snap.docker && typeof snap.docker === "object" ? snap.docker : {}
  var memberOf = workspaceMembership(snap.workspaces)
  var list = Array.isArray(snap.projects) ? snap.projects : []
  var projects = []
  for (var i = 0; i < list.length; i++) {
    var project = normalizeProject(list[i], memberOf)
    if (project) projects.push(project)
  }

  result.ok = true
  result.readOnly = snap.readOnly === true
  result.docker = {
    available: docker.available === true,
    reason: str(docker.reason),
    context: str(docker.contextName),
    error: str(docker.error)
  }
  result.projects = projects
  result.counts = countProjects(projects)
  return result
}

// project id -> workspace name, first workspace wins.
function workspaceMembership(workspaces) {
  var memberOf = {}
  if (!Array.isArray(workspaces)) return memberOf
  for (var w = 0; w < workspaces.length; w++) {
    var workspace = workspaces[w]
    if (!workspace || typeof workspace !== "object") continue
    var members = Array.isArray(workspace.members) ? workspace.members : []
    for (var m = 0; m < members.length; m++) {
      var member = members[m]
      var id = member && typeof member === "object" ? str(member.project) : str(member)
      if (id !== "" && memberOf[id] === undefined) memberOf[id] = str(workspace.name)
    }
  }
  return memberOf
}

function normalizeStatus(value) {
  var status = str(value).toLowerCase()
  return STATUSES.indexOf(status) === -1 ? "stopped" : status
}

function normalizeProject(raw, memberOf) {
  if (!raw || typeof raw !== "object") return null
  var id = str(raw.id)
  var name = str(raw.name) || id
  if (name === "") return null
  var services = Array.isArray(raw.services) ? raw.services : []
  var running = 0
  var unhealthy = []
  for (var i = 0; i < services.length; i++) {
    var service = services[i]
    if (!service || typeof service !== "object") continue
    if (str(service.state) === "running") running++
    if (str(service.health) === "unhealthy") unhealthy.push(str(service.name))
  }
  var warnings = []
  if (Array.isArray(raw.warnings)) {
    for (var j = 0; j < raw.warnings.length; j++) warnings.push(str(raw.warnings[j]))
  }
  return {
    id: id,
    name: name,
    path: str(raw.path),
    status: normalizeStatus(raw.status),
    servicesRunning: running,
    servicesTotal: services.length,
    unhealthy: unhealthy,
    branch: str(raw.gitBranch),
    dirty: raw.gitDirty === true,
    workspace: memberOf && memberOf[id] !== undefined ? memberOf[id] : "",
    appUrl: str(raw.appUrl),
    localDomain: str(raw.localDomain),
    shareUrl: str(raw.shareUrl),
    resolutionError: str(raw.resolutionError),
    warnings: warnings
  }
}

function countProjects(projects) {
  var counts = { total: 0, running: 0, starting: 0, attention: 0, stopped: 0 }
  var list = Array.isArray(projects) ? projects : []
  counts.total = list.length
  for (var i = 0; i < list.length; i++) {
    var status = list[i] ? list[i].status : "stopped"
    if (status === "running") counts.running++
    else if (status === "starting") counts.starting++
    else if (status === "degraded" || status === "failed") counts.attention++
    else counts.stopped++
  }
  return counts
}

// The CLI matches a project by name or path fragment; the IPC surface does
// the same so `omarchy-shell io.github.stackrats.mast start storefront` works
// with whatever the person calls the project.
function findProject(projects, query) {
  var list = Array.isArray(projects) ? projects : []
  var wanted = trim(query)
  if (wanted === "") return null
  var i
  for (i = 0; i < list.length; i++) if (list[i].name === wanted) return list[i]
  for (i = 0; i < list.length; i++) if (list[i].id === wanted) return list[i]
  var suffix = "/" + wanted.replace(/^\/+/, "")
  var matches = []
  for (i = 0; i < list.length; i++) {
    var path = list[i].path
    if (path === wanted || path.slice(-suffix.length) === suffix) matches.push(list[i])
  }
  return matches.length === 1 ? matches[0] : null
}

// ---- What the bar shows.

// The service reports where it got to with the CLI; the snapshot says what
// the CLI answered. One word for the widget, in priority order — the CLI has
// to exist before its answer matters, and a project needing attention
// outranks the ones that are fine.
//
//   checking     first answer not in yet
//   missing      no mast on PATH
//   outdated     mast predates `status --json`
//   error        mast ran but did not answer usefully
//   docker-down  docker unreachable, so nothing can be running
//   attention    a project is degraded or failed
//   running      something is up (or coming up)
//   idle         every project stopped
function widgetState(phase, snapshot) {
  var step = str(phase)
  if (step === "too-old") return "outdated"
  if (step !== "ready") return step === "" ? "checking" : step
  if (!snapshot || !snapshot.ok) return "error"
  if (!snapshot.docker.available) return "docker-down"
  if (snapshot.counts.attention > 0) return "attention"
  if (snapshot.counts.running > 0 || snapshot.counts.starting > 0) return "running"
  return "idle"
}

function stateHasCounts(state) {
  return state === "attention" || state === "running" || state === "idle"
}

// Text beside the mark, "" for icon-only. `ratio` is running/total; a 0/6
// still tells you six projects are known and none is up.
function barLabel(counts, mode, state) {
  if (!stateHasCounts(state)) return ""
  var setting = str(mode)
  if (setting === "none") return ""
  var c = counts || countProjects([])
  if (setting === "running") return String(c.running)
  return c.running + "/" + c.total
}

function iconColorRole(state) {
  return state === "attention" ? "urgent" : "foreground"
}

// Running is full strength; a bar of stopped projects is quiet; a widget that
// cannot answer is quieter still, so a glance says which.
function iconOpacity(state) {
  if (state === "running" || state === "attention") return 1.0
  if (state === "idle") return 0.6
  if (state === "checking" || state === "docker-down") return 0.45
  return 0.35
}

function runningPhrase(counts) {
  var c = counts || countProjects([])
  if (c.total === 0) return "no projects imported"
  var noun = c.total === 1 ? "project" : "projects"
  var text = c.running + " of " + c.total + " " + noun + " running"
  if (c.starting > 0) text += ", " + c.starting + " starting"
  if (c.attention > 0) text += ", " + c.attention + (c.attention === 1 ? " needs" : " need") + " attention"
  return text
}

function dockerReasonPhrase(reason) {
  var why = str(reason)
  if (why === "notInstalled") return "not installed"
  if (why === "notRunning") return "not running"
  if (why === "permissionDenied") return "permission denied"
  if (why === "unreachable") return "unreachable"
  return "unavailable"
}

function tooltipText(state, counts) {
  if (state === "checking") return "Mast · checking…"
  if (state === "missing") return "Mast CLI not found — get it from mast.sh"
  if (state === "outdated") return "Mast CLI needs updating: this build has no status --json"
  if (state === "error") return "Mast · status unavailable"
  if (state === "docker-down") return "Mast · Docker unavailable"
  return "Mast · " + runningPhrase(counts)
}

// ---- What the panel shows.

// PanelHero upper-cases this itself.
function heroMeta(state, snapshot) {
  if (state === "checking") return "Checking…"
  if (state === "missing") return "CLI not found"
  if (state === "outdated") return "CLI needs updating"
  if (state === "error") return "Status unavailable"
  if (state === "docker-down") return "Docker " + dockerReasonPhrase(snapshot && snapshot.docker ? snapshot.docker.reason : "")
  return runningPhrase(snapshot ? snapshot.counts : null)
}

function heroDetail(state, counts) {
  if (!stateHasCounts(state)) return ""
  var c = counts || countProjects([])
  return c.total === 0 ? "" : c.running + "/" + c.total
}

// Title and hint for the card that stands in for the project list while the
// widget cannot show one. "" title means no card.
function guidance(state, snapshot, lastError) {
  if (state === "checking") return { title: "Checking Mast…", hint: "" }
  if (state === "missing") return {
    title: "Mast CLI not found",
    hint: "Install Mast from mast.sh, or point this widget at the binary in its settings. Press w to open the site."
  }
  if (state === "outdated") return {
    title: "Mast CLI needs updating",
    hint: "This build has no `mast status --json`, which the widget reads. Update from mast.sh."
  }
  if (state === "error") return { title: "Mast did not answer", hint: str(lastError) || "Retry with r." }
  if (state === "docker-down") return {
    title: "Docker is " + dockerReasonPhrase(snapshot && snapshot.docker ? snapshot.docker.reason : ""),
    hint: "Mast still lists your projects, but nothing can run until Docker is reachable."
  }
  return { title: "", hint: "" }
}

function statusLabel(status) {
  if (status === "running") return "Running"
  if (status === "starting") return "Starting"
  if (status === "degraded") return "Degraded"
  if (status === "failed") return "Failed"
  return "Stopped"
}

function statusRole(status) {
  if (status === "degraded" || status === "failed") return "urgent"
  if (status === "running" || status === "starting") return "foreground"
  return "dim"
}

function projectMeta(project) {
  if (!project) return ""
  var parts = [statusLabel(project.status)]
  if (project.servicesTotal > 0) {
    parts.push(project.servicesRunning + "/" + project.servicesTotal + (project.servicesTotal === 1 ? " service" : " services"))
  }
  if (project.branch !== "") parts.push(project.branch + (project.dirty ? "*" : ""))
  if (project.workspace !== "") parts.push(project.workspace)
  return parts.join(" · ")
}

// The one thing wrong with a project, when something is: a compose file that
// no longer resolves beats an unhealthy container beats a warning.
function projectNote(project) {
  if (!project) return ""
  if (project.resolutionError !== "") return project.resolutionError
  if (project.unhealthy.length > 0) return "Unhealthy: " + project.unhealthy.join(", ")
  if (project.warnings.length > 0) return project.warnings[0]
  return ""
}

// ---- Turning intent into commands.

function primaryAction(project) {
  var status = project ? project.status : "stopped"
  return status === "running" || status === "starting" || status === "degraded" ? "stop" : "start"
}

function canRestart(project) {
  return !!project && project.status !== "stopped"
}

function actionLabel(verb) {
  var v = str(verb)
  return v === "" ? "" : v.charAt(0).toUpperCase() + v.slice(1)
}

function actionPending(verb, name) {
  return name + ": " + verb + "…"
}

function statusArgv(binary) {
  return [binary, "status", "--json"]
}

function mastArgv(binary, verb, name) {
  return [binary, verb, name]
}

// The trusted https://<domain>.test address wins over the plain APP_URL.
function browserUrl(project) {
  if (!project) return ""
  if (project.localDomain !== "") return "https://" + project.localDomain
  return project.appUrl
}

function deepLink(project) {
  return "mast://project/" + encodeURIComponent(project ? project.name : "")
}

function lines(text) {
  var out = []
  var parts = str(text).split("\n")
  for (var i = 0; i < parts.length; i++) {
    var line = trim(parts[i])
    if (line !== "") out.push(line)
  }
  return out
}

function lastLine(text) {
  var all = lines(text)
  return all.length > 0 ? all[all.length - 1] : ""
}

function elide(text, max) {
  var limit = max || 140
  var value = trim(text).replace(/\s+/g, " ")
  return value.length > limit ? value.substring(0, limit - 1) + "…" : value
}

// A failed `mast status --json` is one of three things: a CLI too old to
// know the flag, an engine that could not be reached, or anything else —
// and the panel reads the last line the CLI printed for that last case,
// which is where the CLI puts the sentence that matters.
function classifyStatusFailure(exitCode, stdout, stderr) {
  var text = str(stderr) + "\n" + str(stdout)
  if (/unexpected argument '--json'/.test(text)) {
    return { kind: "too-old", message: "This Mast CLI has no `status --json`; update it from mast.sh." }
  }
  var reason = lastLine(stderr) || lastLine(stdout)
  return { kind: "error", message: elide(reason || ("mast status failed (exit " + exitCode + ")")) }
}

// The CLI already prefixes its failure line with the project name
// ("docs: port 8080 is taken"); that prefix is dropped rather than said twice.
function actionSummary(verb, name, exitCode, stdout, stderr) {
  if (exitCode === 0) return { ok: true, message: name + ": " + verb + " completed" }
  var reason = lastLine(stderr) || lastLine(stdout)
  var prefix = name + ": "
  if (reason.slice(0, prefix.length) === prefix) reason = trim(reason.slice(prefix.length))
  return { ok: false, message: elide(name + ": " + verb + " failed" + (reason ? " — " + reason : "")) }
}

// The desktop app is optional; the hint for it only appears when a handler
// for mast:// links is there to receive them.
function keyHints(appAvailable) {
  return "enter start/stop · t restart · o open" + (appAvailable ? " · m mast" : "") + " · r refresh · esc close"
}

// Whether anything on this machine answers a mast:// link: the desktop
// binary on the login shell's PATH, or a registered scheme handler whose
// launcher is really Mast (an integrated AppImage registers one; a browser
// that once claimed the scheme does not count). The answer rides on a marked
// line, so a login shell that prints a banner cannot pass for a handler.
var APP_PROBE = "h=$(command -v mast-desktop 2>/dev/null); "
  + "if [ -z \"$h\" ]; then d=$(xdg-mime query default x-scheme-handler/mast 2>/dev/null); "
  + "for dir in \"${XDG_DATA_HOME:-$HOME/.local/share}/applications\" /usr/local/share/applications /usr/share/applications; do "
  + "if [ -n \"$d\" ] && [ -f \"$dir/$d\" ] && grep -qi '^Exec=.*mast' \"$dir/$d\"; then h=\"$dir/$d\"; break; fi; done; fi; "
  + "printf 'MAST_APP=%s\\n' \"$h\""

function appProbeArgv() {
  return ["bash", "-lc", APP_PROBE, "omarchy-mast"]
}

function appAvailableFromProbe(output) {
  var all = lines(output)
  for (var i = all.length - 1; i >= 0; i--) {
    if (all[i].slice(0, 9) === "MAST_APP=") return trim(all[i].slice(9)) !== ""
  }
  return false
}

function refreshIntervalMs(setting, opened) {
  var seconds = clampInt(setting, 30, 5, 3600)
  if (opened) seconds = Math.min(seconds, 10)
  return seconds * 1000
}

if (typeof module !== "undefined") {
  module.exports = {
    APP_LINK: APP_LINK,
    WEBSITE: WEBSITE,
    APP_MISSING: APP_MISSING,
    appProbeArgv: appProbeArgv,
    appAvailableFromProbe: appAvailableFromProbe,
    clampInt: clampInt,
    emptySnapshot: emptySnapshot,
    parseSnapshot: parseSnapshot,
    workspaceMembership: workspaceMembership,
    normalizeStatus: normalizeStatus,
    normalizeProject: normalizeProject,
    countProjects: countProjects,
    findProject: findProject,
    widgetState: widgetState,
    barLabel: barLabel,
    iconColorRole: iconColorRole,
    iconOpacity: iconOpacity,
    runningPhrase: runningPhrase,
    dockerReasonPhrase: dockerReasonPhrase,
    tooltipText: tooltipText,
    heroMeta: heroMeta,
    heroDetail: heroDetail,
    guidance: guidance,
    statusLabel: statusLabel,
    statusRole: statusRole,
    projectMeta: projectMeta,
    projectNote: projectNote,
    primaryAction: primaryAction,
    canRestart: canRestart,
    actionLabel: actionLabel,
    actionPending: actionPending,
    statusArgv: statusArgv,
    mastArgv: mastArgv,
    browserUrl: browserUrl,
    deepLink: deepLink,
    lastLine: lastLine,
    elide: elide,
    classifyStatusFailure: classifyStatusFailure,
    actionSummary: actionSummary,
    keyHints: keyHints,
    refreshIntervalMs: refreshIntervalMs
  }
}
