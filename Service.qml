import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import "Model.js" as Model

// One instance exists per shell, shared by every monitor's bar widget. All
// notification state lives here for that reason: the same logic in the widget
// would fire once per screen.
Item {
  id: root

  property var shell: null
  property var settings: ({})

  property var devices: []
  property var summary: Model.summarize([])

  property var _previous: []
  property var _armState: ({})
  property int _notificationId: 0

  // The shell hands settings to widgets, not services, so the very first
  // device-driven refresh happens before any widget has ever called
  // applySettings and would otherwise diff against threshold: 20,
  // notifyLowBattery: true defaults instead of the user's real settings -
  // and, worse, arm an already-low device against those defaults, so the
  // user's own settings would never produce that device's first
  // notification once they arrived. False until the first applySettings.
  property bool _settingsSeen: false

  // Widgets receive settings from the shell, services do not, so each widget
  // pushes the same object in. With several monitors that means several
  // calls with the same values, so this must stay idempotent and must not
  // restart the diff state (_previous/_armState are always carried forward,
  // never reset to empty).
  //
  // The first call is special: _previous is still empty (refresh() has only
  // been updating the display, see below), so evaluating it now checks the
  // current devices against the user's real settings for the first time - a
  // device already low correctly fires once, under the user's own
  // threshold, exactly as diffEvents' first-seen-low case specifies.
  //
  // Every later call flushes first: it runs the full notifying evaluation
  // under the OLD settings, so a device change that landed inside the
  // debounce window is delivered rather than swallowed by the re-baseline
  // below, THEN adopts the new settings, THEN re-baselines silently via
  // reselect() - a settings change is not a device event and must not
  // announce one (turning showAllDevices off would otherwise read as a
  // burst of disconnects, turning it on as a burst of low-battery events,
  // for devices that never actually changed).
  function applySettings(incoming) {
    if (!incoming) return

    if (!_settingsSeen) {
      settings = incoming
      _settingsSeen = true
      notifyEvents(recompute())
      return
    }

    notifyEvents(recompute())
    settings = incoming
    reselect()
  }

  function setting(key, fallback) {
    if (settings && settings[key] !== undefined) return settings[key]
    return fallback
  }

  function notificationOptions() {
    return {
      threshold: Number(setting("lowBatteryThreshold", 20)),
      notifyLowBattery: setting("notifyLowBattery", true) === true,
      notifyFullyCharged: setting("notifyFullyCharged", true) === true,
      notifyDisconnect: setting("notifyDisconnect", false) === true
    }
  }

  // UPower.devices is an ObjectModel; every other plugin in the shell reads
  // it as a plain array through .values (Mpris.players.values,
  // Pipewire.nodes.values, Bluetooth.devices.values follow the same shape).
  readonly property var upowerDevices: UPower.devices ? UPower.devices.values : []

  function collect() {
    var out = []
    var list = root.upowerDevices
    for (var i = 0; i < list.length; i++) out.push(Model.toDevice(list[i]))
    return out
  }

  // Shared by the device-driven and settings-driven paths: selects devices
  // against the current settings, diffs against the stored snapshot and arm
  // state, updates devices/summary/_previous/_armState, and hands back
  // whatever events the diff produced. Neither the selection nor the diff
  // nor the state update differs between the two callers - only whether the
  // returned events get queued for a notification.
  function recompute() {
    var selected = Model.selectDevices(collect(), setting("showAllDevices", false) === true)
    var result = Model.diffEvents(_previous, selected, _armState, notificationOptions())

    devices = selected
    summary = Model.summarize(selected)
    _previous = selected
    _armState = result.armState

    return result.events
  }

  // Selection only, no diff: what the bar/panel display before the user's
  // real settings have ever arrived. Deliberately does not touch
  // _previous/_armState - diffing here would evaluate against defaults and
  // could arm an already-low device before the user's own threshold has had
  // a chance to see it, which is exactly what leaves it silent forever
  // (Model.diffEvents only announces the transition into "low", not the
  // state of being low).
  function updateDisplayOnly() {
    var selected = Model.selectDevices(collect(), setting("showAllDevices", false) === true)
    devices = selected
    summary = Model.summarize(selected)
  }

  function notifyEvents(events) {
    for (var i = 0; i < events.length; i++) queue(events[i])
    sendNext()
  }

  // Called from an actual UPower device signal (added/removed/changed).
  // Before the first applySettings, only the display is kept current -
  // diffing and notifying wait for the user's real settings so the first
  // evaluation happens against them, not against defaults.
  function refresh() {
    if (!_settingsSeen) {
      updateDisplayOnly()
      return
    }
    notifyEvents(recompute())
  }

  // Re-baselines the selection against new settings without treating the
  // change as a device event. See the comment on applySettings for why.
  function reselect() {
    recompute()
  }

  property var _queue: []

  function queue(event) {
    var pending = _queue.slice(0)
    pending.push(event)
    _queue = pending
  }

  function sendNext() {
    if (_queue.length === 0 || notificationProcess.running) return
    var pending = _queue.slice(0)
    var event = pending.shift()
    _queue = pending
    notificationProcess.command = Model.notificationCommand(event, _notificationId)
    notificationProcess.running = true
  }

  onUpowerDevicesChanged: refreshDebounce.restart()

  // A UPower device changes its own properties in place rather than being
  // replaced, so reacting to the list alone (onUpowerDevicesChanged) is not
  // enough - each device needs its own Connections, exactly the pattern the
  // media plugin's Service.qml uses for Mpris.players (Instantiator over the
  // plain array, delegate: Connections { target: modelData }), not an
  // Instantiator over the ObjectModel with a snapshot-holding QtObject
  // delegate. No first-party plugin in this shell uses the latter shape.
  Instantiator {
    model: root.upowerDevices
    delegate: Connections {
      required property var modelData
      target: modelData
      function onReadyChanged() { refreshDebounce.restart() }
      function onPercentageChanged() { refreshDebounce.restart() }
      function onStateChanged() { refreshDebounce.restart() }
      function onIsPresentChanged() { refreshDebounce.restart() }
      function onTypeChanged() { refreshDebounce.restart() }
      function onModelChanged() { refreshDebounce.restart() }
      function onNativePathChanged() { refreshDebounce.restart() }
      function onPowerSupplyChanged() { refreshDebounce.restart() }
      function onIsLaptopBatteryChanged() { refreshDebounce.restart() }
    }
  }

  Timer {
    id: refreshDebounce
    interval: 150
    repeat: false
    onTriggered: root.refresh()
  }

  // A failed send is not worth a surface of its own. The next event notifies
  // again, and the captured id keeps notifications replacing rather than
  // stacking.
  Process {
    id: notificationProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: notificationStdout
      waitForEnd: true
    }
    onExited: function (exitCode) {
      var id = parseInt(String(notificationStdout.text || "").trim(), 10)
      if (exitCode === 0 && isFinite(id) && id > 0) root._notificationId = id
      root.sendNext()
    }
  }

  readonly property var pipewireNodes: Pipewire.nodes ? Pipewire.nodes.values : []

  readonly property var bluetoothSinks: {
    var list = []
    for (var i = 0; i < pipewireNodes.length; i++) {
      var n = pipewireNodes[i]
      if (n && n.isSink && !n.isStream && String(n.name || "").indexOf("bluez_output.") === 0) list.push(n)
    }
    return list
  }

  // PwNode.properties is invalid until the node is bound, and reading it
  // unbound can destabilize Quickshell's Pipewire service (see the audio
  // panel). Sinks are matched by name, which needs no binding, and only the
  // properties of nodes this tracker binds are ever read.
  PwObjectTracker { objects: root.bluetoothSinks }

  function codecFor(device) {
    var mac = Model.macFromNativePath(device ? device.nativePath : "")
    if (mac === "") return ""
    var sinks = root.bluetoothSinks
    for (var i = 0; i < sinks.length; i++) {
      var node = sinks[i]
      if (!Model.sinkNameMatchesMac(node.name, mac)) continue
      if (!node.ready || !node.properties) return ""
      var codec = node.properties["api.bluez5.codec"]
      return typeof codec === "string" ? codec : ""
    }
    return ""
  }

  // Normalised MAC -> { status, values }. Replaced wholesale on every change,
  // like _queue, so the panel's bindings see each one.
  property var soundcore: ({})

  // A device's setting ids do not change while it stays the same device, so
  // they are fetched once per shell session and only cached on success - a
  // failure (typically the phone app holding the channel) is retried on the
  // next panel open.
  property var _settingIds: ({})

  // openscq30 holds an exclusive channel to the headset, so jobs run one at a
  // time. _currentJob is the one whose process is running, null when idle.
  property var _jobs: []
  property var _currentJob: null

  // Called on panel open, never from a Timer: openscq30 is not a poller. A
  // reopen while anything is still queued or running would only duplicate
  // that work, so it is dropped.
  function refreshSoundcore() {
    if (_currentJob !== null || _jobs.length > 0) return
    if (!_hasBluetoothDevice()) {
      if (Object.keys(soundcore).length > 0) soundcore = ({})
      return
    }
    _enqueueJobs([{ kind: "paired", mac: "", mode: "" }])
    _startNextJob()
  }

  function _hasBluetoothDevice() {
    for (var i = 0; i < devices.length; i++) {
      var device = devices[i]
      if (device.connection === "Bluetooth" && device.isPresent === true
          && Model.macFromNativePath(device.nativePath) !== "") return true
    }
    return false
  }

  // Only a settled "loaded" entry can switch: the click is ignored while
  // loading, switching or unavailable, so repeated clicks queue nothing.
  function cycleMode(mac) {
    var entry = soundcore[mac]
    if (!entry || entry.status !== "loaded") return
    _setSoundcore(mac, { status: "switching", values: entry.values })
    _enqueueJobs([{ kind: "set", mac: mac, mode: Model.nextAmbientMode(entry.values ? entry.values.ambientSoundMode : "") }])
    _startNextJob()
  }

  function _enqueueJobs(jobs) {
    _jobs = _jobs.concat(jobs)
  }

  function _setSoundcore(mac, entry) {
    var next = {}
    for (var key in soundcore) next[key] = soundcore[key]
    next[mac] = entry
    soundcore = next
  }

  function _commandFor(job) {
    if (job.kind === "paired") return Model.OPENSCQ30_PAIRED_COMMAND
    if (job.kind === "ids") return Model.settingIdsCommand(job.mac)
    if (job.kind === "read") return Model.readCommand(job.mac, _settingIds[job.mac])
    if (job.kind === "set") return Model.setModeCommand(job.mac, job.mode)
    return null
  }

  // A job without a command (invalid MAC, no readable setting ids) is
  // completed as a failure on the spot, so it settles its device and the
  // queue keeps moving without a process ever starting.
  function _startNextJob() {
    while (_currentJob === null && _jobs.length > 0) {
      var pending = _jobs.slice(0)
      var job = pending.shift()
      _jobs = pending

      var command = _commandFor(job)
      if (command === null) {
        // Cached ids with no readable setting among them: the device is not
        // one we can show anything for, so it falls back to codec only.
        if (job.kind === "read" && _settingIds.hasOwnProperty(job.mac)) _dropSoundcore(job.mac)
        else _finishJob(job, -1, "")
        continue
      }

      _currentJob = job
      soundcoreProcess.command = command
      soundcoreProcess.running = true
      soundcoreTimeout.restart()
    }
  }

  function _dropSoundcore(mac) {
    var next = {}
    for (var key in soundcore) if (key !== mac) next[key] = soundcore[key]
    soundcore = next
  }

  function _jobEnded(exitCode, text) {
    var job = _currentJob
    if (job === null) return
    soundcoreTimeout.stop()
    _currentJob = null
    _finishJob(job, exitCode, text)
    _startNextJob()
  }

  // stderr is never read: a non-zero exit or stdout that does not parse is
  // all "unavailable" means, whatever openscq30 had to say about it.
  function _finishJob(job, exitCode, text) {
    var ok = exitCode === 0

    if (job.kind === "paired") {
      var paired = ok ? Model.parsePairedDevices(text) : []
      var next = {}
      var follow = []
      for (var i = 0; i < devices.length; i++) {
        var device = devices[i]
        if (device.connection !== "Bluetooth" || device.isPresent !== true) continue
        var mac = Model.macFromNativePath(device.nativePath)
        if (mac === "" || paired.indexOf(mac) === -1 || next[mac] !== undefined) continue
        var previous = soundcore[mac]
        next[mac] = { status: "loading", values: previous ? previous.values : null }
        if (!_settingIds.hasOwnProperty(mac)) follow.push({ kind: "ids", mac: mac, mode: "" })
        follow.push({ kind: "read", mac: mac, mode: "" })
      }
      soundcore = next
      _enqueueJobs(follow)
      return
    }

    // A device dropped by a later paired result (a set queued before it) has
    // nothing left to settle and must not be brought back.
    var entry = soundcore[job.mac]
    if (!entry) return

    if (job.kind === "ids") {
      var ids = ok ? Model.parseSettingIds(text) : null
      if (ids !== null) {
        var cached = {}
        for (var key in _settingIds) cached[key] = _settingIds[key]
        cached[job.mac] = ids
        _settingIds = cached
        return
      }
      _setSoundcore(job.mac, { status: "unavailable", values: entry.values })
      _jobs = _jobs.filter(function (queued) {
        return !(queued.kind === "read" && queued.mac === job.mac)
      })
      return
    }

    if (job.kind === "read") {
      var values = ok ? Model.parseSettingValues(text) : null
      if (values === null && _settingIds.hasOwnProperty(job.mac)) {
        var kept = {}
        for (var id in _settingIds) if (id !== job.mac) kept[id] = _settingIds[id]
        _settingIds = kept
      }
      _setSoundcore(job.mac, values !== null
          ? { status: "loaded", values: values }
          : { status: "unavailable", values: entry.values })
      return
    }

    if (job.kind === "set") {
      var result = ok ? Model.parseSettingValues(text) : null
      if (result !== null && typeof result.ambientSoundMode === "string") {
        var merged = {}
        for (var field in entry.values) merged[field] = entry.values[field]
        merged.ambientSoundMode = result.ambientSoundMode
        _setSoundcore(job.mac, { status: "loaded", values: merged })
        return
      }
      _setSoundcore(job.mac, { status: "unavailable", values: entry.values })
    }
  }

  // Watchdog only: it ends an openscq30 call that never exits so the queue
  // cannot stay locked. It never starts openscq30 - that runs only on panel
  // open and on a mode click, and no Timer may start it.
  Timer {
    id: soundcoreTimeout
    interval: 10000
    repeat: false
    onTriggered: {
      if (soundcoreProcess.running) soundcoreProcess.signal(15)
    }
  }

  Process {
    id: soundcoreProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: soundcoreStdout
      waitForEnd: true
    }
    onExited: function (exitCode) {
      root._jobEnded(exitCode, String(soundcoreStdout.text || ""))
    }
    // A command that fails to start emits no exited, only runningChanged, and
    // would leave _currentJob set and every later refresh blocked. exited and
    // runningChanged come from the same call, so by the deferred check exited
    // has already cleared or replaced the job if it was going to.
    onRunningChanged: {
      if (running || root._currentJob === null) return
      var job = root._currentJob
      Qt.callLater(function () {
        if (root._currentJob === job && !soundcoreProcess.running) root._jobEnded(-1, "")
      })
    }
  }

  Component.onCompleted: refresh()
}
