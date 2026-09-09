import QtQuick
import Quickshell
import Quickshell.Io
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

  // Widgets receive settings from the shell, services do not, so each widget
  // pushes the same object in. Re-running the selection keeps the exposed
  // devices and summary in step with a changed setting (showAllDevices, in
  // particular) without waiting for the next UPower signal, while still
  // threading _previous and _armState through rather than resetting them -
  // the diff state is carried forward, not restarted. This must stay silent:
  // see reselect() below for why.
  function applySettings(incoming) {
    if (!incoming) return
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

  // Called from an actual UPower device signal (added/removed/changed). A
  // real battery event, so its notifications are queued and sent.
  function refresh() {
    var events = recompute()
    for (var i = 0; i < events.length; i++) queue(events[i])
    sendNext()
  }

  // Called when a widget pushes settings. Changing showAllDevices or
  // notifyDisconnect changes which devices are *selected*, not anything any
  // device actually did - turning showAllDevices off drops peripherals out
  // of the selection and would otherwise read as a burst of "disconnected"
  // events, and turning it on would read as a burst of "low" events for
  // devices that were already below the threshold. So this path re-baselines
  // devices/summary/_previous/_armState exactly like refresh() (the arm
  // state Model.diffEvents returns still marks an already-low device as
  // armed, so it won't fire spuriously on the next device-driven refresh
  // either, and re-arms normally once its level recovers past the
  // hysteresis margin) but discards the events instead of queuing them.
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

  Component.onCompleted: refresh()
}
