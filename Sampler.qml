import QtQuick
import Qt.labs.folderlistmodel
import Quickshell.Io

// Reads CPU and memory usage straight out of procfs. No subprocesses, no
// interpreter, no polling helper — three FileViews and a timer.
//
// One subtlety drives the whole shape of this file: FileView.reload() is
// asynchronous even with blockLoading set, so text() sampled right after a
// reload() still returns the previous contents. Every parse therefore hangs
// off onLoaded, which fires once the fresh contents are in.
Item {
  id: root

  visible: false

  // Sampling period. CPU percentages are jiffy deltas between consecutive
  // samples, so this is also the averaging window.
  property int intervalMs: 2000

  // Number of samples kept for the sparklines.
  property int historyLength: 40

  // Per-core, swap and load average are only parsed while something is
  // looking at them. The bar widget alone needs neither.
  property bool detailed: false

  // ------------------------------------------------------------ readouts
  property real cpuFraction: 0        // 0..1, all cores aggregated
  property var cpuCores: []           // [0..1] per core, only while detailed
  property real memFraction: 0        // 0..1, (total - available) / total
  property real memTotalKb: 0
  property real memUsedKb: 0
  property real swapFraction: 0
  property real swapTotalKb: 0
  property real swapUsedKb: 0
  property var loadAvg: [0, 0, 0]
  property var cpuHistory: []
  property var memHistory: []
  property bool primed: false         // false until the first CPU delta exists
  property string cpuModel: ""        // read once; the CPU does not change
  property real uptimeSeconds: 0
  property real cpuTemp: 0            // °C, 0 when no CPU sensor was found

  readonly property int coreCount: cpuCores.length

  function reset() {
    priv.prevAggregate = null
    priv.prevCores = []
    cpuHistory = []
    memHistory = []
    primed = false
  }

  QtObject {
    id: priv
    property var prevAggregate: null
    property var prevCores: []
  }

  // /proc/stat's cpu lines are cumulative jiffy counters. Usage over a window
  // is (busy delta / total delta); idle and iowait both count as idle.
  function _counters(fields) {
    var total = 0
    for (var i = 1; i < fields.length; i++) {
      var n = Number(fields[i])
      if (isFinite(n)) total += n
    }
    return { idle: (Number(fields[4]) || 0) + (Number(fields[5]) || 0), total: total }
  }

  function _usage(now, before) {
    if (!before) return 0
    var dTotal = now.total - before.total
    if (dTotal <= 0) return 0
    var dIdle = now.idle - before.idle
    return Math.max(0, Math.min(1, (dTotal - dIdle) / dTotal))
  }

  function _push(history, value) {
    var next = history.slice(Math.max(0, history.length - historyLength + 1))
    next.push(value)
    return next
  }

  function _parseStat(text) {
    var lines = text.split("\n")
    var aggregate = null
    var cores = []

    for (var i = 0; i < lines.length; i++) {
      if (lines[i].indexOf("cpu") !== 0) break
      var fields = lines[i].split(/\s+/)
      if (fields[0] === "cpu") aggregate = _counters(fields)
      else if (detailed) cores.push(_counters(fields))
    }
    if (!aggregate) return

    if (priv.prevAggregate) {
      cpuFraction = _usage(aggregate, priv.prevAggregate)
      cpuHistory = _push(cpuHistory, cpuFraction)
      primed = true
    }
    priv.prevAggregate = aggregate

    if (detailed && cores.length > 0) {
      if (priv.prevCores.length === cores.length) {
        var usage = []
        for (var c = 0; c < cores.length; c++) usage.push(_usage(cores[c], priv.prevCores[c]))
        cpuCores = usage
      }
      priv.prevCores = cores
    } else if (!detailed && cpuCores.length > 0) {
      cpuCores = []
      priv.prevCores = []
    }
  }

  function _parseMeminfo(text) {
    var lines = text.split("\n")
    var values = {}
    for (var i = 0; i < lines.length; i++) {
      var parts = lines[i].split(/:?\s+/)
      if (parts.length >= 2) values[parts[0]] = Number(parts[1]) || 0
    }

    var total = values["MemTotal"] || 0
    if (total <= 0) return
    // MemAvailable is the kernel's own estimate of what is reclaimable, which
    // is what "used" should mean — MemFree alone counts cache as used.
    var used = total - (values["MemAvailable"] || 0)
    memTotalKb = total
    memUsedKb = Math.max(0, used)
    memFraction = Math.max(0, Math.min(1, used / total))
    memHistory = _push(memHistory, memFraction)

    var swapTotal = values["SwapTotal"] || 0
    swapTotalKb = swapTotal
    swapUsedKb = Math.max(0, swapTotal - (values["SwapFree"] || 0))
    swapFraction = swapTotal > 0 ? Math.max(0, Math.min(1, swapUsedKb / swapTotal)) : 0
  }

  function _parseLoadavg(text) {
    var parts = text.split(/\s+/)
    loadAvg = [Number(parts[0]) || 0, Number(parts[1]) || 0, Number(parts[2]) || 0]
  }

  function _parseUptime(text) {
    uptimeSeconds = Number(String(text).split(/\s+/)[0]) || 0
  }

  // "Intel(R) Core(TM) Ultra X7 358H" is a marketing string, not a name. Strip
  // the trademark noise and the clock suffix so the hero reads like a machine.
  function _parseCpuinfo(text) {
    var lines = text.split("\n")
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].indexOf("model name") !== 0) continue
      var value = lines[i].split(":").slice(1).join(":")
      cpuModel = value
        .replace(/\((R|TM|r|tm)\)/g, "")
        .replace(/\s+(CPU|Processor)\b/g, "")
        .replace(/\s*@.*$/, "")
        .replace(/\s+/g, " ")
        .replace(/^\s+|\s+$/g, "")
      return
    }
  }

  // ------------------------------------------------------ CPU temperature
  //
  // hwmon numbering follows driver probe order, so /sys/class/hwmon/hwmon6 is
  // coretemp on this boot and could be anything on the next. The sensor has to
  // be found by *name*: enumerate the directories, read each `name`, and keep
  // the best-ranked CPU driver. Ranking rather than first-match makes the
  // choice independent of scan order.
  //
  // Machines with no CPU sensor at all (most VMs) simply leave cpuTemp at 0,
  // and the panel omits the line.
  readonly property var _sensorRanks: ({
    "coretemp": 0,      // Intel
    "k10temp": 1,       // AMD (Zen and later)
    "zenpower": 2,      // AMD, out-of-tree driver
    "cpu_thermal": 3,   // ARM SoCs
    "cpu-thermal": 4,
    "acpitz": 5         // last resort: ACPI thermal zone, often the chassis
  })

  property string tempPath: ""
  property int _tempRank: 99

  function _considerSensor(dirPath, name) {
    var key = String(name).replace(/^\s+|\s+$/g, "")
    if (!(key in _sensorRanks)) return
    var rank = _sensorRanks[key]
    if (rank >= _tempRank) return
    _tempRank = rank
    tempPath = dirPath + "/temp1_input"
  }

  function _parseTemp(text) {
    // millidegrees Celsius
    var milli = Number(String(text).replace(/^\s+|\s+$/g, ""))
    cpuTemp = isFinite(milli) && milli > 0 ? milli / 1000 : 0
  }

  FolderListModel {
    id: hwmonDirs
    folder: "file:///sys/class/hwmon"
    showDirs: true
    showFiles: false
    showDotAndDotDot: false
    sortField: FolderListModel.Name
  }

  // One FileView per hwmon directory, alive only long enough to read its name.
  Instantiator {
    model: hwmonDirs
    delegate: FileView {
      required property string filePath
      path: filePath + "/name"
      blockLoading: true
      printErrors: false
      onLoaded: root._considerSensor(filePath, text())
    }
  }

  FileView {
    id: tempFile
    path: root.tempPath
    blockLoading: true
    printErrors: false
    onLoaded: root._parseTemp(text())
    onLoadFailed: root.cpuTemp = 0
  }

  FileView {
    id: statFile
    path: "/proc/stat"
    blockLoading: true
    onLoaded: root._parseStat(text())
  }

  FileView {
    id: memFile
    path: "/proc/meminfo"
    blockLoading: true
    onLoaded: root._parseMeminfo(text())
  }

  FileView {
    id: loadFile
    path: "/proc/loadavg"
    blockLoading: true
    onLoaded: root._parseLoadavg(text())
  }

  FileView {
    id: uptimeFile
    path: "/proc/uptime"
    blockLoading: true
    onLoaded: root._parseUptime(text())
  }

  // /proc/cpuinfo is comparatively large (a block per thread) and its model
  // name never changes, so it is read once at startup and never reloaded.
  FileView {
    id: cpuinfoFile
    path: "/proc/cpuinfo"
    blockLoading: true
    onLoaded: root._parseCpuinfo(text())
  }

  Timer {
    interval: root.intervalMs
    running: true
    repeat: true
    onTriggered: {
      statFile.reload()
      memFile.reload()
      if (root.detailed) {
        loadFile.reload()
        uptimeFile.reload()
        if (root.tempPath !== "") tempFile.reload()
      }
    }
  }

  // Switching into detailed mode mid-flight has no previous per-core sample to
  // diff against, so the first detailed tick would read as 0% on every core.
  // Reloading immediately establishes that baseline a tick early instead.
  onDetailedChanged: {
    if (detailed) {
      statFile.reload()
      loadFile.reload()
      uptimeFile.reload()
      if (tempPath !== "") tempFile.reload()
    }
  }
}
