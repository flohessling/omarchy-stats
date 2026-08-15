import QtQuick
import qs.Commons

// One panel section: title, headline percentage, a supporting detail line and
// the history strip the bar widget shows in miniature.
Column {
  id: root

  property string title: ""
  property string icon: ""
  property string detail: ""
  property string value: ""
  property real fraction: 0
  property var history: []
  property string fontFamily: Style.font.family
  property color textColor: Color.foreground
  property color dimColor: Qt.darker(textColor, 1.55)
  property color lineColor: Color.accent
  property real chartHeight: Style.space(34)

  spacing: Style.space(4)

  Item {
    width: parent.width
    height: Math.max(heading.implicitHeight, headline.implicitHeight)

    Text {
      id: heading
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: root.icon === "" ? root.title : root.icon + "  " + root.title
      color: root.dimColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      renderType: Text.NativeRendering
    }

    Text {
      id: headline
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: root.value
      color: root.textColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.heading
      renderType: Text.NativeRendering
    }
  }

  Text {
    visible: root.detail !== ""
    text: root.detail
    color: root.dimColor
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    renderType: Text.NativeRendering
  }

  Sparkline {
    width: parent.width
    height: root.chartHeight
    values: root.history
    strokeColor: root.lineColor
    strokeWidth: Math.max(1, Style.spaceReal(1.5))
  }
}
