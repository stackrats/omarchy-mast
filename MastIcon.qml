import QtQuick
import qs.Commons

// The Mast mark drawn natively: a five-by-five pixel "M", the same block
// letter the CLI prints in its banner, so it survives being twelve pixels
// tall in a bar slot where an SVG would smear. Colour and opacity are the
// caller's; the badge is a small filled dot for "something needs attention".
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground
  property bool badge: false
  property color badgeColor: Color.urgent
  property color badgeBorderColor: Color.bar.background

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  // Row-major, five cells per row; 1 paints a block.
  readonly property var cells: [
    1, 0, 0, 0, 1,
    1, 1, 0, 1, 1,
    1, 0, 1, 0, 1,
    1, 0, 0, 0, 1,
    1, 0, 0, 0, 1
  ]
  readonly property real cell: iconSize / 5
  readonly property real gap: Math.max(0.5, cell * 0.14)

  Repeater {
    model: root.cells

    Rectangle {
      required property var modelData
      required property int index
      visible: modelData === 1
      x: (index % 5) * root.cell + root.gap / 2
      y: Math.floor(index / 5) * root.cell + root.gap / 2
      width: root.cell - root.gap
      height: root.cell - root.gap
      radius: Math.max(0.5, width * 0.18)
      color: root.color
      antialiasing: true
    }
  }

  Rectangle {
    visible: root.badge
    width: Math.max(5, root.iconSize * 0.42)
    height: width
    radius: width / 2
    color: root.badgeColor
    border.width: Math.max(1, Math.round(width * 0.18))
    border.color: root.badgeBorderColor
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.rightMargin: -width * 0.28
    anchors.bottomMargin: -width * 0.28
  }
}
