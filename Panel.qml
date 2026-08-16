import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar readout for CPU and memory, plus a detail panel on click.
//
// The bar half never spawns a process: everything it shows comes from
// procfs reads inside the shell process (see Sampler.qml). The panel adds
// one short-lived helper for the process list, and only while it is open.
Panel {
  id: root

  moduleName: "flohessling.stats"
  ipcTarget: "flohessling.stats"

  // ------------------------------------------------------------- settings
  readonly property int barIntervalMs: Math.max(500, setting("intervalMs", 2000))
  readonly property int panelIntervalMs: Math.max(500, setting("panelIntervalMs", 1000))
  readonly property bool showSparklines: setting("sparklines", true)
  readonly property int topProcessCount: Math.max(0, setting("topProcesses", 5))
  readonly property int alertPercent: setting("alertPercent", 90)
  readonly property string chartColorToken: setting("chartColor", Color.pick("stats.chart", "accent"))
  readonly property string chartAlertColorToken: setting("chartAlertColor", Color.pick("stats.chart-alert", "urgent"))
  readonly property bool showCores: setting("cores", true)
  readonly property string cpuIcon: setting("cpuIcon", "")
  readonly property string memoryIcon: setting("memoryIcon", "")
  readonly property string clickCommand: setting("clickCommand", "omarchy-launch-or-focus-tui btop")

  // ---------------------------------------------------------------- theme
  readonly property bool vertical: bar ? bar.vertical : false
  readonly property color foreground: bar ? bar.barForeground : Color.foreground
  readonly property color panelText: Color.popups.text
  readonly property color accent: Color.accent
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(panelText, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Chart colors are theme *token references*, not literals, resolved in three
  // steps: an explicit per-instance setting, else a `[stats]` section the theme
  // published in its own shell.*.toml, else accent/urgent, which every theme
  // has. Color.flatColor then accepts a role name ("accent", "urgent"), any
  // shell.toml key ("hyprland.active-border"), or a plain hex — and re-resolves
  // on theme switch, because both it and Color.pick read Color.shellValues.
  //
  // The theme step matters because Quattro's palette has no green: colors.toml
  // `red`/`color1` becomes Color.urgent, but `color2` never gets a semantic
  // name. Letting the theme name its own chart colors keeps that decision where
  // the rest of the palette lives, instead of in every user's shell.json.
  readonly property color chartColor: Color.flatColor(chartColorToken, Color.accent)
  readonly property color chartAlertColor: Color.flatColor(chartAlertColorToken, Color.urgent)

  function chartColorFor(fraction) {
    return fraction * 100 >= alertPercent ? chartAlertColor : chartColor
  }

  property var topProcesses: []

  function gb(kb) { return (kb / 1048576).toFixed(1) }
  function pct(fraction) { return Math.round(fraction * 100) + "%" }

  // "omarchy-launch-or-focus-tui btop" -> "Open btop". The command is a
  // setting, so the label is derived rather than hardcoded: take the last
  // argument that is not a flag, and drop any leading path.
  function commandLabel(command) {
    var tokens = String(command || "").split(/\s+/).filter(function(t) {
      return t.length > 0 && t.charAt(0) !== "-"
    })
    if (tokens.length === 0) return "Run command"
    var last = tokens[tokens.length - 1]
    return "Open " + last.split("/").pop()
  }

  function uptimeText(seconds) {
    if (!(seconds > 0)) return "—"
    var days = Math.floor(seconds / 86400)
    var hours = Math.floor((seconds % 86400) / 3600)
    var minutes = Math.floor((seconds % 3600) / 60)
    if (days > 0) return days + "d " + hours + "h"
    if (hours > 0) return hours + "h " + minutes + "m"
    return minutes + "m"
  }
  function alertColor(fraction, normal) {
    return fraction * 100 >= alertPercent ? urgent : normal
  }

  function applyTopProcesses(text) {
    var rows = []
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].length === 0) continue
      var f = lines[i].split("\t")
      if (f.length < 4) continue
      rows.push({ pid: f[0], name: f[1], cpu: Number(f[2]) || 0, rssKb: Number(f[3]) || 0 })
    }
    topProcesses = rows
  }

  Sampler {
    id: stats
    intervalMs: root.opened ? root.panelIntervalMs : root.barIntervalMs
    detailed: root.opened
    historyLength: 48
  }

  // The helper lives next to this file; Process wants a path, not a URL.
  readonly property string helperPath: Qt.resolvedUrl("stats-top").toString().replace(/^file:\/\//, "")

  Process {
    id: topProc
    command: [root.helperPath, String(root.topProcessCount), "0.4"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.applyTopProcesses(text) }
  }

  Timer {
    interval: Math.max(1500, root.panelIntervalMs * 2)
    running: root.opened && root.topProcessCount > 0
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!topProc.running) topProc.running = true
  }

  onOpenedChanged: if (!opened) topProcesses = []

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ------------------------------------------------------------ bar entry
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    active: root.opened
    fixedWidth: root.vertical ? -1 : Math.round(readouts.implicitWidth + Style.spaceReal(9) * 2)
    fixedHeight: root.vertical ? Math.round(readouts.implicitHeight + Style.spaceReal(5) * 2) : -1
    tooltipText: "CPU " + root.pct(stats.cpuFraction)
      + "  ·  RAM " + root.gb(stats.memUsedKb) + " / " + root.gb(stats.memTotalKb) + " GB"
    onPressed: function(b) {
      if (b === Qt.RightButton && root.clickCommand !== "" && root.bar) root.bar.run(root.clickCommand)
      else root.toggle()
    }

    // One column per metric on a horizontal bar, stacked on a vertical one.
    Grid {
      id: readouts
      anchors.centerIn: parent
      columns: root.vertical ? 1 : 2
      spacing: Style.space(root.vertical ? 2 : 9)

      BarMetric {
        icon: root.cpuIcon
        fraction: stats.cpuFraction
        ready: stats.primed
        history: stats.cpuHistory
        showSparkline: root.showSparklines && !root.vertical
        fontFamily: root.fontFamily
        textColor: root.alertColor(stats.cpuFraction, root.foreground)
        accentColor: root.chartColorFor(stats.cpuFraction)
      }

      BarMetric {
        icon: root.memoryIcon
        fraction: stats.memFraction
        history: stats.memHistory
        showSparkline: root.showSparklines && !root.vertical
        fontFamily: root.fontFamily
        textColor: root.alertColor(stats.memFraction, root.foreground)
        accentColor: root.chartColorFor(stats.memFraction)
      }
    }
  }

  // --------------------------------------------------------------- panel
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        // ---------- Hero: chip · CPU model · machine facts · btop ----------
        PanelHero {
          width: parent.width
          title: "System Stats"
          // The panel names itself; the machine identifies itself underneath.
          // Core count and total memory stay out — the meter row already shows
          // one bar per core and the memory block reads "7.9 / 30.9 GB".
          meta: stats.cpuModel
          foreground: root.panelText
          fontFamily: root.fontFamily

          iconComponent: Component {
            Text {
              text: root.cpuIcon
              color: root.panelText
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              renderType: Text.NativeRendering
            }
          }

          trailingControl: Component {
            Button {
              visible: root.clickCommand !== ""
              iconText: ""
              tooltipText: root.commandLabel(root.clickCommand)
              foreground: root.panelText
              fontFamily: root.fontFamily
              iconSize: Style.font.subtitle * 1.5
              horizontalPadding: Style.space(5)
              verticalPadding: Style.space(2)
              onClicked: {
                if (root.bar) root.bar.run(root.clickCommand)
                root.close()
              }
            }
          }
        }

        PanelSeparator { foreground: root.panelText }

        MetricBlock {
          width: parent.width
          title: "CPU"
          icon: root.cpuIcon
          // Core count lives in the hero now; repeating it here is noise.
          detail: ""
          fraction: stats.cpuFraction
          value: stats.primed ? root.pct(stats.cpuFraction) : "--%"
          history: stats.cpuHistory
          fontFamily: root.fontFamily
          textColor: root.panelText
          dimColor: root.dim
          lineColor: root.chartColorFor(stats.cpuFraction)
        }

        // Per-core load. A column per core reads as one shape, so an
        // unbalanced machine (one core pinned, the rest idle) is obvious at a
        // glance in a way a single aggregate number never is.
        Row {
          id: coreRow
          visible: root.showCores && stats.coreCount > 0
          width: parent.width
          spacing: Style.space(2)

          readonly property real cellWidth: stats.coreCount > 0
            ? (width - (stats.coreCount - 1) * spacing) / stats.coreCount
            : 0

          Repeater {
            model: stats.cpuCores

            Rectangle {
              required property var modelData

              width: coreRow.cellWidth
              height: Style.space(26)
              radius: Style.space(2)
              color: Qt.rgba(root.panelText.r, root.panelText.g, root.panelText.b, 0.08)

              Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: Math.max(1, parent.height * Math.max(0, Math.min(1, modelData)))
                radius: parent.radius
                // Each core alerts on its own load, against the same threshold
                // as the aggregate — a saturated core is worth seeing even when
                // the average across 16 of them stays calm.
                color: root.chartColorFor(modelData)

                Behavior on height {
                  NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }
              }
            }
          }
        }

        PanelSeparator { foreground: root.panelText }

        MetricBlock {
          width: parent.width
          title: "MEMORY"
          icon: root.memoryIcon
          detail: root.gb(stats.memUsedKb) + " / " + root.gb(stats.memTotalKb) + " GB"
          fraction: stats.memFraction
          value: root.pct(stats.memFraction)
          history: stats.memHistory
          fontFamily: root.fontFamily
          textColor: root.panelText
          dimColor: root.dim
          lineColor: root.chartColorFor(stats.memFraction)
        }

        // Facts that do not deserve a chart.
        Row {
          width: parent.width
          spacing: Style.space(16)

          Repeater {
            model: [
              { label: "SWAP", value: stats.swapTotalKb > 0
                  ? root.gb(stats.swapUsedKb) + " / " + root.gb(stats.swapTotalKb) + " GB"
                  : "off" },
              { label: "LOAD", value: stats.loadAvg[0].toFixed(2) + "  " + stats.loadAvg[1].toFixed(2) + "  " + stats.loadAvg[2].toFixed(2) },
              { label: "UPTIME", value: root.uptimeText(stats.uptimeSeconds) }
            ]

            Column {
              required property var modelData
              spacing: Style.space(2)

              Text {
                text: modelData.label
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                renderType: Text.NativeRendering
              }

              Text {
                text: modelData.value
                color: root.panelText
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                renderType: Text.NativeRendering
              }
            }
          }
        }

        PanelSeparator {
          visible: root.topProcessCount > 0
          foreground: root.panelText
        }

        Column {
          visible: root.topProcessCount > 0
          width: parent.width
          spacing: Style.space(6)

          PanelSectionHeader {
            text: "TOP PROCESSES"
            foreground: root.panelText
            fontFamily: root.fontFamily
          }

          Repeater {
            model: root.topProcesses

            Item {
              required property var modelData
              width: parent.width
              height: Style.space(16)

              Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - cpuText.width - memText.width - Style.space(16)
                elide: Text.ElideRight
                text: modelData.name
                color: root.panelText
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                renderType: Text.NativeRendering
              }

              Text {
                id: cpuText
                anchors.right: memText.left
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.cpu.toFixed(0) + "%"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                renderType: Text.NativeRendering
              }

              Text {
                id: memText
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: (modelData.rssKb / 1024).toFixed(0) + " MB"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                renderType: Text.NativeRendering
              }
            }
          }
        }
      }
    }
  }
}
