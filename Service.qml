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

  Component.onCompleted: refresh()
}
