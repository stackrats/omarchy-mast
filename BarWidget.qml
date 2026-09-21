import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The Mast mark in the bar with a running/total project count, and the host
// for the projects panel. Left click opens the panel, middle click refreshes,
// right click raises the Mast desktop app.
//
// This file owns the Service and the IPC target; Panel.qml is loaded beside
// it and handed the button to anchor against — the same split the built-in
// clock and weather widgets use.
BarWidget {
  id: root
  moduleName: "io.github.stackrats.mast"

  Service {
    id: mast
    settings: root.settings
    opened: root.opened
  }

  readonly property string labelMode: String(setting("label", "ratio"))
  readonly property bool hideWhenUnavailable: setting("hideWhenUnavailable", false) === true
  readonly property string labelText: vertical ? "" : Model.barLabel(mast.counts, labelMode, mast.state)
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property bool attention: mast.state === "attention"
  readonly property real markOpacity: Model.iconOpacity(mast.state)
  readonly property bool shown: !(hideWhenUnavailable && mast.state === "missing")

  function refresh() {
    mast.refresh()
  }

  function act(verb, name) {
    var project = Model.findProject(mast.projects, name)
    if (!project) return "unknown project: " + String(name || "")
    return mast.run(verb, project) ? "ok" : "busy"
  }

  // ---- Panel. Shape contract for shell.summon/hide/toggle routing:
  //      Bar.findPanelWidget requires open/close/opened on the widget root.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  // Forwarded so this widget can stand in for the panel as the bar's popout
  // identity: Bar.requestPopout prefers closeForPopoutSwitch over close, and
  // KeyboardPanel reads popoutSwitchClosing back off its owner.
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("service" in target) target.service = mast
  }

  visible: shown
  implicitWidth: shown ? button.implicitWidth : 0
  implicitHeight: shown ? button.implicitHeight : 0

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "io.github.stackrats.mast"

    function refresh(): void { root.broadcast("refresh") }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function start(project: string): string { return root.act("start", project) }
    function stop(project: string): string { return root.act("stop", project) }
    function restart(project: string): string { return root.act("restart", project) }
    function state(): string { return JSON.stringify({ state: mast.state, counts: mast.counts }) }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical ? -1 : Math.round(content.implicitWidth + button.scaledHorizontalMargin * 2)
    fixedHeight: root.vertical ? Style.bar.iconSlot : -1
    tooltipText: Model.tooltipText(mast.state, mast.counts)

    onPressed: function(b) {
      if (b === Qt.RightButton) mast.openApp()
      else if (b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }

    Row {
      id: content
      anchors.centerIn: parent
      spacing: Style.space(5)

      MastIcon {
        anchors.verticalCenter: parent.verticalCenter
        iconSize: Math.round(Style.bar.iconCanvas * 0.85)
        color: button.foreground
        opacity: root.markOpacity
        badge: root.attention
        badgeColor: root.urgent
        badgeBorderColor: root.bar ? root.bar.background : Color.bar.background

        Behavior on opacity {
          NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
        }
      }

      Text {
        visible: root.labelText !== ""
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.labelText
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: Style.font.body
        renderType: Text.NativeRendering
      }
    }
  }
}
