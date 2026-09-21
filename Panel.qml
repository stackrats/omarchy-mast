import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The projects panel: a hero with the overall picture, one row per project
// with its state, services, branch and workspace, and the lifecycle verbs on
// each row. Keyboard first — j/k walk the rows, enter starts or stops.
//
// BarWidget.qml owns the bar pill, the Service and the IPC target; it hands
// this panel the button to anchor against and the service to read.
Panel {
  id: root
  moduleName: "io.github.stackrats.mast"
  manageIpc: false

  property var anchorItem: null
  // The bar identifies a panel by the widget mounted in its slot — the
  // BarWidget — not this nested item. Popout coordination compares against
  // that, so it has to be what this panel calls itself to the bar.
  property var hostWidget: null
  property var service: null
  readonly property var barIdentity: hostWidget || root

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string state: service ? service.state : "checking"
  readonly property var projects: service ? service.projects : []
  readonly property var counts: service ? service.counts : Model.countProjects([])
  readonly property var snapshot: service ? service.snapshot : Model.emptySnapshot()
  readonly property bool refreshing: service ? service.refreshing : false
  readonly property bool busy: service ? service.busy : false
  readonly property string busyProject: service ? service.busyProject : ""
  readonly property string lastError: service ? service.lastError : ""
  readonly property string actionStatus: service ? service.actionStatus : ""
  readonly property bool actionFailed: service ? service.actionFailed : false
  readonly property bool readOnly: snapshot.readOnly === true
  // Counts mean something only once the CLI has answered.
  readonly property bool ready: state === "running" || state === "idle" || state === "attention"
  readonly property bool cliUsable: state !== "missing" && state !== "outdated"
  readonly property var guidance: Model.guidance(state, snapshot, lastError)

  property int projectIndex: 0
  property bool cursorActive: false
  // "header" is the hero's trailing button; "projects" the rows.
  property string focusSection: "projects"

  function open() {
    if (service) service.refresh()
    root.controller.show()
    // Set after showing: showing hands the popout coordinator over, which
    // closes whichever panel was open, and that close clears the shared flag.
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function refresh() {
    if (service) service.refresh()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // Summoning by hotkey moves no pointer, so a hover the bar was still
  // holding must not keep the center indicators revealed behind the panel.
  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  // ---- Cursor.

  function ensureCursor() {
    if (projects.length === 0) {
      focusSection = "header"
      projectIndex = 0
      return
    }
    if (focusSection !== "header") focusSection = "projects"
    if (projectIndex >= projects.length) projectIndex = projects.length - 1
    if (projectIndex < 0) projectIndex = 0
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    ensureCursor()
    if (dy === 0) return
    if (focusSection === "header") {
      if (dy > 0 && projects.length > 0) {
        focusSection = "projects"
        projectIndex = 0
        scrollCursorIntoView()
      }
      return
    }
    if (dy < 0 && projectIndex === 0) {
      setHeaderCursor()
      return
    }
    projectIndex = Math.max(0, Math.min(projects.length - 1, projectIndex + dy))
    scrollCursorIntoView()
  }

  function selectedProject() {
    if (projects.length === 0) return null
    return projects[Math.max(0, Math.min(projectIndex, projects.length - 1))]
  }

  function setProjectCursor(index) {
    cursorActive = true
    focusSection = "projects"
    projectIndex = index
  }

  function setHeaderCursor() {
    cursorActive = true
    focusSection = "header"
    if (panelFlick) panelFlick.contentY = 0
  }

  function activateHeader() {
    if (cliUsable) refresh()
    else if (service) service.openWebsite()
  }

  function activateCursor() {
    ensureCursor()
    if (focusSection === "header") activateHeader()
    else togglePrimary(selectedProject())
  }

  function togglePrimary(project) {
    if (service && project && cliUsable) service.togglePrimary(project)
  }

  function restartProject(project) {
    if (service && project && cliUsable && Model.canRestart(project)) service.restart(project)
  }

  function openInBrowser(project) {
    if (service && project) service.openInBrowser(project)
  }

  function openInMast(project) {
    if (service && project) service.openInMast(project)
  }

  function scrollItemIntoView(item) {
    if (!panelFlick || !item) return
    Qt.callLater(function() {
      if (!item) return
      var margin = Style.space(6)
      var point = item.mapToItem(panelFlick.contentItem, 0, 0)
      var top = point.y
      var bottom = top + item.height
      var viewTop = panelFlick.contentY
      var viewBottom = viewTop + panelFlick.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < viewTop + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > viewBottom - margin) panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  function scrollCursorIntoView() {
    if (focusSection === "projects" && projectColumn && projectIndex >= 0 && projectIndex < projectColumn.children.length)
      scrollItemIntoView(projectColumn.children[projectIndex])
  }

  onOpenedChanged: {
    if (!opened) return
    cursorActive = false
    focusSection = projects.length > 0 ? "projects" : "header"
    if (panelFlick) panelFlick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onProjectIndexChanged: scrollCursorIntoView()
  onProjectsChanged: ensureCursor()

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) {
          root.cursorActive = true
          root.ensureCursor()
          return
        }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh()
        else if (t === "s" || t === "S") root.togglePrimary(root.selectedProject())
        else if (t === "t" || t === "T") root.restartProject(root.selectedProject())
        else if (t === "o" || t === "O") root.openInBrowser(root.selectedProject())
        else if (t === "m" || t === "M") root.openInMast(root.selectedProject())
        else if (t === "w" || t === "W") { if (root.service) root.service.openWebsite() }
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          // ---------- Hero: mark · title/meta · count pill · refresh ----------
          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            // The hero's components resolve `root` to the hero itself, so
            // everything they need is mirrored here under a name of its own.
            readonly property bool ringVisible: root.cursorActive && root.focusSection === "header"
            readonly property bool cliUsable: root.cliUsable
            readonly property bool refreshing: root.refreshing
            readonly property bool attention: root.state === "attention"
            readonly property real markOpacity: Model.iconOpacity(root.state)
            readonly property color foreground: root.foreground
            readonly property color urgent: root.urgent
            function focusHero() { root.setHeaderCursor() }
            function activate() { root.activateHeader() }

            PanelHero {
              id: hero
              width: parent.width
              title: "Mast"
              meta: Model.heroMeta(root.state, root.snapshot)
              detail: Model.heroDetail(root.state, root.counts)
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: header.markOpacity
              iconComponent: Component {
                MastIcon {
                  iconSize: Style.font.display
                  color: header.foreground
                  badge: header.attention
                  badgeColor: header.urgent
                  badgeBorderColor: Color.popups.background
                }
              }

              // Refresh while the CLI answers; the way to mast.sh when it
              // cannot. The header's only cursor target either way.
              trailingControl: Component {
                PanelActionButton {
                  iconText: header.cliUsable ? "󰑐" : "󰏌"
                  tooltipText: header.cliUsable ? "Refresh" : "Open mast.sh"
                  foreground: hero.foreground
                  fontFamily: hero.fontFamily
                  hasCursor: header.ringVisible
                  enabled: !header.cliUsable || !header.refreshing
                  onHovered: function(on) { if (on) header.focusHero() }
                  onClicked: header.activate()
                }
              }
            }
          }

          // ---------- Last action, or why there is nothing to show ----------
          Text {
            textFormat: Text.PlainText
            visible: root.actionStatus !== ""
            width: parent.width
            text: root.actionStatus
            color: root.actionFailed ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            textFormat: Text.PlainText
            visible: root.readOnly && root.ready
            width: parent.width
            text: "Read-only: another Mast build owns this machine's engine, so start and stop will be refused."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          GuidanceCard {
            visible: root.guidance.title !== ""
            width: parent.width
            title: root.guidance.title
            hint: root.guidance.hint
          }

          // ---------- Projects ----------
          PanelSeparator {
            visible: root.projects.length > 0 || root.ready
            foreground: root.foreground
          }

          Column {
            visible: root.projects.length > 0 || root.ready
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "PROJECTS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              textFormat: Text.PlainText
              visible: root.projects.length === 0
              width: parent.width
              text: "No projects imported yet — add them in the Mast app."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
            }

            Column {
              id: projectColumn
              visible: root.projects.length > 0
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: root.projects
                ProjectRow {
                  required property var modelData
                  required property int index
                  width: projectColumn.width
                  project: modelData
                  rowIndex: index
                }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: root.projects.length > 0
            width: parent.width
            text: Model.keyHints()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }

  component GuidanceCard: BorderSurface {
    id: card
    property string title: ""
    property string hint: ""

    radius: Style.cornerRadius
    color: Style.normalFillFor(root.foreground, Color.accent)
    borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
    implicitHeight: cardColumn.implicitHeight + Style.space(20)

    Column {
      id: cardColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)
      spacing: Style.space(4)

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: card.title
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: true
        wrapMode: Text.WordWrap
      }

      Text {
        textFormat: Text.PlainText
        visible: card.hint !== ""
        width: parent.width
        text: card.hint
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }
  }

  component ProjectRow: CursorSurface {
    id: projectRow
    property var project: null
    property int rowIndex: 0

    readonly property string name: project ? String(project.name) : ""
    readonly property string verb: Model.primaryAction(project)
    readonly property string note: Model.projectNote(project)
    readonly property string url: Model.browserUrl(project)
    readonly property bool busyHere: name !== "" && root.busyProject === name
    readonly property bool starting: !!project && project.status === "starting"
    readonly property string role: project ? Model.statusRole(project.status) : "dim"
    readonly property color dotColor: role === "urgent" ? root.urgent : (role === "dim" ? root.dim : root.foreground)

    hasCursor: root.cursorActive && root.focusSection === "projects" && root.projectIndex === rowIndex
    foreground: root.foreground
    implicitHeight: rowContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setProjectCursor(projectRow.rowIndex)
      onClicked: root.togglePrimary(projectRow.project)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      Item {
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: Style.space(10)
        implicitHeight: Style.space(10)

        Rectangle {
          id: dot
          anchors.centerIn: parent
          width: Style.space(8)
          height: width
          radius: width / 2
          color: projectRow.dotColor

          Behavior on color { ColorAnimation { duration: 200 } }

          // Pulses while the project is coming up, or while a verb is in
          // flight on it, so the row itself says something is happening.
          SequentialAnimation on opacity {
            running: projectRow.busyHere || projectRow.starting
            loops: Animation.Infinite
            alwaysRunToEnd: true
            NumberAnimation { from: 1.0; to: 0.3; duration: 600; easing.type: Easing.InOutSine }
            NumberAnimation { from: 0.3; to: 1.0; duration: 600; easing.type: Easing.InOutSine }
          }
        }
      }

      ColumnLayout {
        id: rowContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: projectRow.name
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: Model.projectMeta(projectRow.project)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          visible: projectRow.note !== ""
          Layout.fillWidth: true
          text: projectRow.note
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      PanelActionButton {
        iconText: projectRow.verb === "stop" ? "󰓛" : "󰐊"
        tooltipText: Model.actionLabel(projectRow.verb)
        foreground: root.foreground
        hoverColor: projectRow.verb === "stop" ? root.urgent : root.foreground
        fontFamily: root.fontFamily
        enabled: root.cliUsable && !root.busy
        Layout.alignment: Qt.AlignVCenter
        onClicked: root.togglePrimary(projectRow.project)
      }

      PanelActionButton {
        iconText: "󰜉"
        tooltipText: "Restart"
        visible: Model.canRestart(projectRow.project)
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: root.cliUsable && !root.busy
        Layout.alignment: Qt.AlignVCenter
        onClicked: root.restartProject(projectRow.project)
      }

      PanelActionButton {
        iconText: "󰖟"
        tooltipText: projectRow.url !== "" ? "Open " + projectRow.url : ""
        visible: projectRow.url !== ""
        foreground: root.foreground
        fontFamily: root.fontFamily
        Layout.alignment: Qt.AlignVCenter
        onClicked: root.openInBrowser(projectRow.project)
      }

      PanelActionButton {
        iconText: "󰏌"
        tooltipText: "Open in Mast"
        foreground: root.foreground
        fontFamily: root.fontFamily
        Layout.alignment: Qt.AlignVCenter
        onClicked: root.openInMast(projectRow.project)
      }
    }
  }
}
