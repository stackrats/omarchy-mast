# Mast for Omarchy

Your [Laravel Sail](https://laravel.com/docs/sail) projects in the Omarchy bar.

[Mast](https://mast.sh) is a desktop control center for Sail: every project, its containers, logs, workers and services in one place, without replacing Sail or Docker. This plugin puts the part you glance at most into the bar, and the verbs you reach for most into a panel one click or one keystroke away.

- **In the bar:** the Mast mark with a running/total project count. It dims when everything is stopped, and carries a badge when a project is degraded or failed.
- **In the panel:** one row per project with its state, running services, git branch and workspace. Start, stop or restart a project, open it in the browser at its trusted `https://` address, or jump to it in the Mast app.
- **Keyboard first:** `j`/`k` walk the rows, `enter` starts or stops, and every action has a key.
- **Honest when it cannot help:** if the `mast` CLI is missing, outdated, or Docker is down, the panel says so and what to do, instead of an empty list.

## Requirements

- [Omarchy](https://omarchy.org) with the Quattro shell (the plugin system).
- The `mast` CLI, from [mast.sh](https://mast.sh), on your login shell `PATH` or pointed at in the widget settings. The widget reads `mast status --json`, so it needs a Mast release that has that flag.
- Docker, reachable by your user, for anything to actually run.
- Optional: the Mast desktop app, for "Open in Mast". `mast://` links only navigate — they select a project — so this button never starts or stops anything by itself. Without the app (or with a stale `mast://` handler whose launcher is gone) the row button and its key stay hidden, and the bar's right-click and the `m` key open mast.sh instead.

The plugin uses one Omarchy helper that ships with the shell, `omarchy-launch-browser`, to open web addresses.

## Install

```bash
omarchy plugin add https://github.com/stackrats/omarchy-mast.git --enable
```

Plugins land in `~/.config/omarchy/plugins/io.github.stackrats.mast/`. The widget starts in the bar's right section; move it with:

```bash
omarchy bar move io.github.stackrats.mast --section center
```

Update later with `omarchy plugin update io.github.stackrats.mast`, which shows the diff before fast-forwarding. If the bar looks unchanged afterwards, the shell kept the previous instance of the widget around; `omarchy restart shell` clears it.

## Remove

```bash
omarchy plugin remove io.github.stackrats.mast --yes
```

That disables the widget and deletes the checkout. The plugin writes nothing outside its own folder and never touches your Mast or Sail configuration.

## Using it

| Where | Input | Does |
|---|---|---|
| Bar | left click | open or close the panel |
| Bar | middle click | refresh now |
| Bar | right click | raise the Mast desktop app |
| Panel | `j` / `k`, arrows | move between projects |
| Panel | `enter` / `space` / click | start a stopped project, stop a running one |
| Panel | `s` | same as enter |
| Panel | `t` | restart the selected project |
| Panel | `o` | open the selected project in the browser |
| Panel | `m` | open the selected project in Mast |
| Panel | `r` | refresh |
| Panel | `w` | open mast.sh (when the CLI is missing or outdated) |
| Panel | `tab` / `shift+tab` | switch to the neighbouring bar panel |
| Panel | `esc` | close |

Each row also has the buttons: start or stop, restart (only for projects that are up), open in browser (only when the project has an address), and open in Mast (only when the desktop app, or a registered `mast://` handler, is present on the machine).

The browser button prefers the project's trusted local domain (`https://myapp.test`, set up in Mast) and falls back to `APP_URL` from `.env`.

## Settings

Edit them from the bar's widget settings, or inline on the widget's entry in `~/.config/omarchy/shell.json`.

| Key | Default | Meaning |
|---|---|---|
| `refreshIntervalSec` | `30` | How often the bar polls `mast status --json`, 5–3600. The panel polls every 10 s (or faster, if configured) while it is open. |
| `label` | `ratio` | `ratio` shows running/total, `running` shows only the running count, `none` shows just the mark. Vertical bars always show just the mark. |
| `hideWhenUnavailable` | `false` | Remove the widget from the bar, instead of dimming the mark, when `mast` is not installed. |
| `mastBinary` | `""` | Absolute path to the `mast` executable. Empty finds it on your login shell `PATH`. |

## Shell IPC

The widget registers `io.github.stackrats.mast` as an IPC target, so keybindings and scripts can drive it:

```bash
omarchy-shell io.github.stackrats.mast toggle
omarchy-shell io.github.stackrats.mast refresh
omarchy-shell io.github.stackrats.mast start storefront     # name, id, or path suffix
omarchy-shell io.github.stackrats.mast stop storefront
omarchy-shell io.github.stackrats.mast restart storefront
omarchy-shell io.github.stackrats.mast state                # {"state":"running","counts":{...}}
```

`open`, `close`, `show` and `hide` exist too. A Hyprland binding to summon the panel:

```
bindd = SUPER CTRL, M, Mast projects, exec, omarchy-shell shell toggle io.github.stackrats.mast
```

## What it runs

Everything the plugin executes is an argv vector, never a shell string built from a project name:

- `mast status --json` on each poll.
- `mast start|stop|restart <project>` when you ask.
- `omarchy-launch-browser <url>` for the browser button and mast.sh.
- The Mast launcher the probe found (`mast-desktop` on `PATH`, or the executable behind the registered `mast://` handler) with the link as its argument. Never `xdg-open`, which would hand a link the app failed to take to a browser.
- One `bash -l` login shell, to find `mast` on your profile's `PATH` (the shell process that hosts plugins inherits Hyprland's environment, not your profile).

No privilege escalation, no network access of its own, no install hooks, no writes outside its folder. Plugins run unsandboxed inside the Omarchy shell, so read the source before enabling it — it is short.

## Development

Clone it somewhere and add that path as the plugin, so edits are live (the shell reloads plugin code on save):

```bash
git clone https://github.com/stackrats/omarchy-mast.git ~/code/omarchy-mast
omarchy plugin add ~/code/omarchy-mast --enable
```

Checks, which CI also runs:

```bash
bash test/run.sh           # manifest wiring, Model.js under node, qmllint when present
scripts/validate.sh        # the same manifest rules `omarchy plugin validate` enforces
omarchy plugin validate .  # on an Omarchy machine
```

Layout:

| File | Role |
|---|---|
| `manifest.json` | Plugin identity, settings schema, entry point |
| `BarWidget.qml` | Entry point: the bar pill, the IPC target, hosts the panel |
| `Panel.qml` | The popup: hero, guidance, project rows, keyboard handling |
| `Service.qml` | Finds `mast`, polls status, runs verbs, tracks the last outcome |
| `Model.js` | Pure parsing and wording, unit-tested under node |
| `MastIcon.qml` | The pixel-M mark, drawn natively so it stays crisp at bar size |

`Model.js` is where behaviour lives; the QML files only bind to it. Add a test to `test/model-test.sh` for anything you change there.

## License

MIT — see [LICENSE](LICENSE). Mast itself is also MIT, at [stackrats/mast](https://github.com/stackrats/mast).
