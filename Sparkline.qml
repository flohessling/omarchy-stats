import QtQuick

// A history strip. Values are 0..1, oldest first; the canvas is only
// repainted when the array changes, which is once per sample.
Canvas {
  id: root

  property var values: []
  property color strokeColor: "white"
  property real fillAlpha: 0.16
  // Sparklines that autoscale hide the difference between an idle machine and
  // a busy one, so the vertical axis stays pinned to 0..1.
  property real strokeWidth: 1

  antialiasing: true
  onValuesChanged: requestPaint()
  onStrokeColorChanged: requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    if (!values || values.length === 0 || width <= 0 || height <= 0) return

    var count = values.length
    var usable = Math.max(1, height - strokeWidth)
    var step = count > 1 ? width / (count - 1) : width
    var top = strokeWidth / 2

    function pointX(i) { return count > 1 ? i * step : width / 2 }
    function pointY(i) {
      var v = Math.max(0, Math.min(1, Number(values[i]) || 0))
      return top + (1 - v) * usable
    }

    ctx.beginPath()
    ctx.moveTo(pointX(0), pointY(0))
    for (var i = 1; i < count; i++) ctx.lineTo(pointX(i), pointY(i))

    if (fillAlpha > 0) {
      ctx.save()
      ctx.lineTo(pointX(count - 1), height)
      ctx.lineTo(pointX(0), height)
      ctx.closePath()
      ctx.fillStyle = Qt.rgba(strokeColor.r, strokeColor.g, strokeColor.b, fillAlpha)
      ctx.fill()
      ctx.restore()
    }

    ctx.beginPath()
    ctx.moveTo(pointX(0), pointY(0))
    for (var j = 1; j < count; j++) ctx.lineTo(pointX(j), pointY(j))
    ctx.strokeStyle = strokeColor
    ctx.lineWidth = strokeWidth
    ctx.lineJoin = "round"
    ctx.stroke()
  }
}
