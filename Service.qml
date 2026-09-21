import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

// Talks to the Mast CLI so the widget and the panel never have to: finds the
// binary, polls `mast status --json`, runs start/stop/restart, and keeps the
// last answer plus a one-line account of whatever happened last.
//
// Everything runs as argv vectors — no shell string is ever built from a
// project name. The one login shell is the lookup of the binary itself.
Item {
  id: root

  property var settings: ({})
  // The panel polls faster while someone is looking at it.
  property bool opened: false

  // Where mast was found; "" until resolved. The lookup goes through a login
  // shell because the shell process hosting this plugin inherits Hyprland's
  // environment rather than the user's profile, and the CLI installs to
  // ~/.local/bin by default — the profile is what puts that on PATH.
  property string mastPath: ""
  // "checking" | "missing" | "too-old" | "error" | "ready"
  property string phase: "checking"
  property bool refreshing: false
  property string lastError: ""
  property string actionStatus: ""
  property bool actionFailed: false
  property string busyProject: ""
  property string busyVerb: ""
  property var snapshot: Model.emptySnapshot()

  readonly property bool installed: mastPath !== ""
  readonly property var projects: snapshot.projects
  readonly property var counts: snapshot.counts
  // Not `state`: an Item already has one, and shadowing it is asking for a
  // silent binding to the wrong thing.
  readonly property string widgetState: Model.widgetState(phase, snapshot)
  // Whether a mast:// link has anywhere to go on this machine.
  property bool appAvailable: false
  readonly property bool busy: actionProcess.running
  readonly property string configuredBinary: String(setting("mastBinary", "") || "").trim()
  readonly property int refreshIntervalMs: Model.refreshIntervalMs(setting("refreshIntervalSec", 30), opened)

  property string _resolveOut: ""
  property string _appOut: ""
  property string _statusOut: ""
  property string _statusErr: ""
  property string _actionOut: ""
  property string _actionErr: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function refresh() {
    if (!appProbe.running) {
      _appOut = ""
      appProbe.command = Model.appProbeArgv()
      appProbe.running = true
    }
    if (statusProcess.running || resolveProcess.running) return
    if (mastPath === "") {
      resolve()
      return
    }
    pollStatus()
  }

  function resolve() {
    refreshing = true
    _resolveOut = ""
    resolveProcess.command = ["bash", "-lc", 'command -v -- "$1"', "omarchy-mast",
      configuredBinary !== "" ? configuredBinary : "mast"]
    resolveProcess.running = true
  }

  // A changed setting is a new binary to find; forget the old one.
  onConfiguredBinaryChanged: {
    mastPath = ""
    phase = "checking"
    refresh()
  }

  function pollStatus() {
    _statusOut = ""
    _statusErr = ""
    refreshing = true
    statusProcess.command = Model.statusArgv(mastPath)
    statusProcess.running = true
    // Armed per poll and never re-armed by a poll that was skipped, so a
    // hung CLI is reaped inside one interval instead of parking the widget.
    pollWatchdog.restart()
  }

  function run(verb, project) {
    if (!project || busy || mastPath === "") return false
    var name = String(project.name || "")
    if (name === "") return false
    _actionOut = ""
    _actionErr = ""
    busyProject = name
    busyVerb = verb
    actionFailed = false
    actionStatus = Model.actionPending(verb, name)
    actionProcess.command = Model.mastArgv(mastPath, verb, name)
    actionProcess.running = true
    actionWatchdog.restart()
    return true
  }

  function start(project) { return run("start", project) }
  function stop(project) { return run("stop", project) }
  function restart(project) { return run("restart", project) }
  function togglePrimary(project) { return run(Model.primaryAction(project), project) }

  function openInBrowser(project) {
    var url = Model.browserUrl(project)
    if (url === "") return false
    Quickshell.execDetached(["omarchy-launch-browser", url])
    return true
  }

  // mast:// links only navigate — they select a project in the desktop app,
  // never start or stop anything — so this is safe to fire at an app that
  // may or may not be running. mast-desktop forwards to a running window and
  // launches one otherwise; xdg-open covers an AppImage that registered the
  // scheme but sits off PATH.
  function openLink(link) {
    if (!appAvailable) {
      // Handing the link to xdg-open without a handler lands it in a browser
      // tab that cannot do anything with it; say what is missing instead.
      actionStatus = Model.APP_MISSING
      actionFailed = true
      return false
    }
    Quickshell.execDetached(["bash", "-lc",
      'if command -v mast-desktop >/dev/null 2>&1; then exec mast-desktop "$1"; else exec xdg-open "$1"; fi',
      "omarchy-mast", link])
    return true
  }

  function openInMast(project) {
    return openLink(project ? Model.deepLink(project) : Model.APP_LINK)
  }

  function openApp() {
    return openLink(Model.APP_LINK)
  }

  function openWebsite() {
    Quickshell.execDetached(["omarchy-launch-browser", Model.WEBSITE])
  }

  function applyStatus(exitCode, stdout, stderr) {
    refreshing = false
    if (exitCode === 0) {
      var parsed = Model.parseSnapshot(stdout)
      if (parsed.ok) {
        snapshot = parsed
        phase = "ready"
        lastError = ""
      } else {
        phase = "error"
        lastError = parsed.error
      }
      return
    }
    var failure = Model.classifyStatusFailure(exitCode, stdout, stderr)
    phase = failure.kind === "too-old" ? "too-old" : "error"
    lastError = failure.message
    // The last good snapshot stays: one missed poll should not empty the
    // panel, and the state word already says the picture may be stale.
  }

  function finishAction(exitCode, stdout, stderr) {
    var summary = Model.actionSummary(busyVerb, busyProject, exitCode, stdout, stderr)
    actionStatus = summary.message
    actionFailed = !summary.ok
    busyProject = ""
    busyVerb = ""
    actionWatchdog.stop()
    if (summary.ok) actionStatusTimer.restart()
    // Once for the containers, once more for health to settle.
    settleRefresh.restart()
    lateRefresh.restart()
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalMs
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: settleRefresh
    interval: 1500
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: lateRefresh
    interval: 8000
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: pollWatchdog
    interval: 25000
    repeat: false
    onTriggered: {
      if (statusProcess.running) statusProcess.running = false
      if (resolveProcess.running) resolveProcess.running = false
    }
  }

  // A compose `up` that pulls images can legitimately take minutes; only a
  // CLI that has clearly wedged gets reaped, so the row stops looking busy.
  Timer {
    id: actionWatchdog
    interval: 600000
    repeat: false
    onTriggered: if (actionProcess.running) actionProcess.running = false
  }

  Timer {
    id: actionStatusTimer
    interval: 6000
    repeat: false
    onTriggered: if (!root.actionFailed) root.actionStatus = ""
  }

  Process {
    id: resolveProcess
    running: false
    command: []
    stdout: StdioCollector { id: resolveStdout; waitForEnd: true; onStreamFinished: root._resolveOut = text }
    onExited: function(exitCode) {
      var found = String(resolveStdout.text || root._resolveOut || "").trim().split("\n")[0]
      if (exitCode === 0 && found !== "") {
        root.mastPath = found
        root.pollStatus()
      } else {
        root.mastPath = ""
        root.phase = "missing"
        root.refreshing = false
        root.lastError = ""
      }
    }
  }

  Process {
    id: appProbe
    running: false
    command: []
    stdout: StdioCollector { id: appProbeStdout; waitForEnd: true; onStreamFinished: root._appOut = text }
    onExited: function(exitCode) {
      root.appAvailable = exitCode === 0 && Model.appAvailableFromProbe(String(appProbeStdout.text || root._appOut || ""))
    }
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true; onStreamFinished: root._statusOut = text }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true; onStreamFinished: root._statusErr = text }
    onExited: function(exitCode) {
      pollWatchdog.stop()
      root.applyStatus(exitCode,
        String(statusStdout.text || root._statusOut || ""),
        String(statusStderr.text || root._statusErr || ""))
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true; onStreamFinished: root._actionOut = text }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true; onStreamFinished: root._actionErr = text }
    onExited: function(exitCode) {
      root.finishAction(exitCode,
        String(actionStdout.text || root._actionOut || ""),
        String(actionStderr.text || root._actionErr || ""))
    }
  }
}
