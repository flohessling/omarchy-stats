import QtQuick
import qs.Commons

// One bar readout: glyph, optional history strip, percentage. Sized to its
// content so the widget can hand the total width to WidgetButton.fixedWidth.
Row {
  id: root

  property string icon: ""
  property real fraction: 0
  property bool showSparkline: true
  property var history: []
  property color accentColor: Color.accent
  property color textColor: Color.foreground
  property string fontFamily: Style.font.family
  property int fontSize: Style.font.caption
  property real sparklineWidth: Style.spaceReal(22)
  property bool ready: true

  spacing: Style.space(4)
  // Percentages are drawn in a fixed-width slot so the row does not jitter as
  // the number goes 9% -> 10% -> 100%.
  readonly property real valueWidth: metrics.advanceWidth

  TextMetrics {
    id: metrics
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    text: "100%"
  }

  Text {
    anchors.verticalCenter: parent.verticalCenter
    text: root.icon
    color: root.textColor
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    renderType: Text.NativeRendering
  }

  Sparkline {
    anchors.verticalCenter: parent.verticalCenter
    visible: root.showSparkline
    width: visible ? root.sparklineWidth : 0
    height: Math.max(6, Math.round(root.fontSize * 0.85))
    values: root.history
    strokeColor: root.accentColor
  }

  Text {
    anchors.verticalCenter: parent.verticalCenter
    width: root.valueWidth
    horizontalAlignment: Text.AlignRight
    text: root.ready ? Math.round(root.fraction * 100) + "%" : "--%"
    color: root.textColor
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    renderType: Text.NativeRendering
  }
}
