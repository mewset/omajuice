const test = require("node:test")
const assert = require("node:assert/strict")

const Model = require("../Model.js")

test("connectionFor reads the transport out of the native path", () => {
  assert.equal(Model.connectionFor("/sys/devices/pci0000:00/usb1/1-2"), "USB")
  assert.equal(Model.connectionFor("/org/bluez/hci0/dev_AC_80_0A"), "Bluetooth")
  assert.equal(Model.connectionFor(""), "Unknown")
  assert.equal(Model.connectionFor(null), "Unknown")
})

test("connectionFor is case insensitive", () => {
  assert.equal(Model.connectionFor("/sys/devices/USB1/1-2"), "USB")
})

test("toDevice maps a UPower device onto a plain object", () => {
  const device = Model.toDevice({
    model: "Jabra Evolve2 65",
    type: Model.DeviceType.Headset,
    percentage: 42.6,
    state: Model.DeviceState.Discharging,
    isPresent: true,
    isLaptopBattery: false,
    powerSupply: false,
    nativePath: "/org/bluez/hci0/dev_AC_80_0A"
  })

  assert.equal(device.key, "/org/bluez/hci0/dev_AC_80_0A")
  assert.equal(device.model, "Jabra Evolve2 65")
  assert.equal(device.type, Model.DeviceType.Headset)
  assert.equal(device.percentage, 43)
  assert.equal(device.state, Model.DeviceState.Discharging)
  assert.equal(device.isPresent, true)
  assert.equal(device.connection, "Bluetooth")
})

test("toDevice keys by model when the native path is empty", () => {
  const device = Model.toDevice({ model: "Sony WH-1000XM4", nativePath: "" })
  assert.equal(device.key, "Sony WH-1000XM4")
})

test("toDevice survives a device with nothing set", () => {
  const device = Model.toDevice({})
  assert.equal(device.model, "Unknown device")
  assert.equal(device.key, "Unknown device")
  assert.equal(device.percentage, 0)
  assert.equal(device.isPresent, false)
  assert.equal(device.connection, "Unknown")
})

test("audio device types match on type alone", () => {
  const types = [
    Model.DeviceType.Headset,
    Model.DeviceType.Headphones,
    Model.DeviceType.Speakers,
    Model.DeviceType.OtherAudio
  ]
  for (const type of types) {
    const device = Model.toDevice({ model: "Nameless", type, nativePath: "/x" })
    assert.equal(Model.isAudioDevice(device), true, `type ${type} should match`)
  }
})

test("non-audio types never match, whatever they are called", () => {
  const device = Model.toDevice({
    model: "Logitech MX Master",
    type: Model.DeviceType.Mouse,
    nativePath: "/x"
  })
  assert.equal(Model.isAudioDevice(device), false)
})

test("ambiguous types fall back to the keyword list", () => {
  const bluetooth = Model.toDevice({
    model: "Sony WH-1000XM4",
    type: Model.DeviceType.BluetoothGeneric,
    nativePath: "/org/bluez/hci0/dev_AC"
  })
  const unknown = Model.toDevice({
    model: "SteelSeries Arctis 7",
    type: Model.DeviceType.Unknown,
    nativePath: "/sys/devices/usb1"
  })
  assert.equal(Model.isAudioDevice(bluetooth), true)
  assert.equal(Model.isAudioDevice(unknown), true)
})

test("an ambiguous device nobody recognises does not match", () => {
  const device = Model.toDevice({
    model: "Acme Widget 3000",
    type: Model.DeviceType.BluetoothGeneric,
    nativePath: "/org/bluez/hci0/dev_11"
  })
  assert.equal(Model.isAudioDevice(device), false)
})

test("the keyword list also matches against the native path", () => {
  const device = Model.toDevice({
    model: "",
    type: Model.DeviceType.Unknown,
    nativePath: "/sys/devices/usb1/1-2/hyperx_cloud"
  })
  assert.equal(Model.isAudioDevice(device), true)
})

test("keyword matching ignores case", () => {
  assert.equal(Model.matchesKeyword("JABRA ELITE 85H"), true)
  assert.equal(Model.matchesKeyword("Bose QuietComfort 45"), true)
  assert.equal(Model.matchesKeyword(""), false)
  assert.equal(Model.matchesKeyword(null), false)
})

function device(overrides) {
  return Model.toDevice(Object.assign({
    model: "Jabra Evolve2 65",
    type: Model.DeviceType.Headset,
    percentage: 50,
    state: Model.DeviceState.Discharging,
    isPresent: true,
    nativePath: "/org/bluez/hci0/dev_AC"
  }, overrides))
}

test("selectDevices keeps audio devices and drops the rest", () => {
  const devices = [
    device({ model: "Jabra Evolve2 65", nativePath: "/a" }),
    device({ model: "Dell Monitor", type: Model.DeviceType.Monitor, nativePath: "/b" })
  ]
  const selected = Model.selectDevices(devices, false)
  assert.equal(selected.length, 1)
  assert.equal(selected[0].model, "Jabra Evolve2 65")
})

test("selectDevices with showAllDevices keeps every peripheral", () => {
  const devices = [
    device({ model: "Jabra Evolve2 65", nativePath: "/a" }),
    device({ model: "Logitech MX Master", type: Model.DeviceType.Mouse, nativePath: "/b" })
  ]
  assert.equal(Model.selectDevices(devices, true).length, 2)
})

test("selectDevices always drops the laptop battery and the mains supply", () => {
  const devices = [
    device({ model: "Internal Battery", type: Model.DeviceType.Battery, isLaptopBattery: true, nativePath: "/a" }),
    device({ model: "AC Adapter", type: Model.DeviceType.LinePower, nativePath: "/b" }),
    device({ model: "Some Battery", type: Model.DeviceType.Battery, powerSupply: true, nativePath: "/c" })
  ]
  assert.equal(Model.selectDevices(devices, true).length, 0)
})

test("selectDevices sorts by level ascending and leaves the input alone", () => {
  const devices = [
    device({ percentage: 80, nativePath: "/a" }),
    device({ percentage: 12, nativePath: "/b" }),
    device({ percentage: 45, nativePath: "/c" })
  ]
  const selected = Model.selectDevices(devices, false)
  assert.deepEqual(selected.map(d => d.percentage), [12, 45, 80])
  assert.equal(devices[0].percentage, 80)
})

test("summarize reports the lowest level and the count", () => {
  const summary = Model.summarize([
    device({ percentage: 12, nativePath: "/a" }),
    device({ percentage: 80, nativePath: "/b" })
  ])
  assert.equal(summary.count, 2)
  assert.equal(summary.lowest, 12)
  assert.equal(summary.device.percentage, 12)
  assert.equal(summary.charging, false)
})

test("summarize reports charging when any device is charging", () => {
  const summary = Model.summarize([
    device({ percentage: 12, state: Model.DeviceState.Charging, nativePath: "/a" })
  ])
  assert.equal(summary.charging, true)
})

test("summarize ignores absent devices so they cannot drag the reading down", () => {
  const summary = Model.summarize([
    device({ percentage: 0, isPresent: false, nativePath: "/a" }),
    device({ percentage: 60, nativePath: "/b" })
  ])
  assert.equal(summary.count, 1)
  assert.equal(summary.lowest, 60)
})

test("summarize on an empty list reports nothing", () => {
  const summary = Model.summarize([])
  assert.equal(summary.count, 0)
  assert.equal(summary.lowest, -1)
  assert.equal(summary.device, null)
  assert.equal(summary.charging, false)
})

const options = { threshold: 20, notifyLowBattery: true, notifyFullyCharged: true, notifyDisconnect: true }

test("a device crossing the threshold notifies once", () => {
  const before = [device({ percentage: 30, nativePath: "/a" })]
  const after = [device({ percentage: 18, nativePath: "/a" })]

  const first = Model.diffEvents(before, after, {}, options)
  assert.equal(first.events.length, 1)
  assert.equal(first.events[0].kind, "low")
  assert.equal(first.events[0].percentage, 18)

  const second = Model.diffEvents(after, [device({ percentage: 15, nativePath: "/a" })], first.armState, options)
  assert.equal(second.events.length, 0)
})

test("a charging device never reports low battery", () => {
  const after = [device({ percentage: 5, state: Model.DeviceState.Charging, nativePath: "/a" })]
  const result = Model.diffEvents([], after, {}, options)
  assert.equal(result.events.length, 0)
})

test("low battery re-arms only above the threshold plus hysteresis", () => {
  const low = [device({ percentage: 10, nativePath: "/a" })]
  const armed = Model.diffEvents([], low, {}, options)
  assert.equal(armed.events.length, 1)

  const nudged = Model.diffEvents(low, [device({ percentage: 22, nativePath: "/a" })], armed.armState, options)
  assert.equal(nudged.armState["/a"].lowNotified, true)

  const recovered = Model.diffEvents(low, [device({ percentage: 40, nativePath: "/a" })], armed.armState, options)
  assert.equal(recovered.armState["/a"].lowNotified, false)
})

test("reaching full charge notifies once on the transition", () => {
  const before = [device({ percentage: 99, state: Model.DeviceState.Charging, nativePath: "/a" })]
  const after = [device({ percentage: 100, state: Model.DeviceState.FullyCharged, nativePath: "/a" })]

  const first = Model.diffEvents(before, after, {}, options)
  assert.equal(first.events.length, 1)
  assert.equal(first.events[0].kind, "charged")

  const second = Model.diffEvents(after, after, first.armState, options)
  assert.equal(second.events.length, 0)
})

test("a device first seen already full does not notify", () => {
  const after = [device({ percentage: 100, state: Model.DeviceState.FullyCharged, nativePath: "/a" })]
  const result = Model.diffEvents([], after, {}, options)
  assert.equal(result.events.length, 0)
})

test("a device leaving the list reports a disconnect", () => {
  const before = [device({ nativePath: "/a" })]
  const result = Model.diffEvents(before, [], {}, options)
  assert.equal(result.events.length, 1)
  assert.equal(result.events[0].kind, "disconnected")
})

test("a device going absent reports a disconnect", () => {
  const before = [device({ nativePath: "/a" })]
  const after = [device({ isPresent: false, nativePath: "/a" })]
  const result = Model.diffEvents(before, after, {}, options)
  assert.equal(result.events.length, 1)
  assert.equal(result.events[0].kind, "disconnected")
})

test("each notification kind can be switched off independently", () => {
  const quiet = { threshold: 20, notifyLowBattery: false, notifyFullyCharged: false, notifyDisconnect: false }
  const low = Model.diffEvents([], [device({ percentage: 5, nativePath: "/a" })], {}, quiet)
  const gone = Model.diffEvents([device({ nativePath: "/b" })], [], {}, quiet)
  assert.equal(low.events.length, 0)
  assert.equal(gone.events.length, 0)
})

test("arm state is dropped for devices that are gone", () => {
  const armed = Model.diffEvents([], [device({ percentage: 5, nativePath: "/a" })], {}, options)
  const after = Model.diffEvents([device({ percentage: 5, nativePath: "/a" })], [], armed.armState, options)
  assert.equal(after.armState["/a"], undefined)
})

test("arm state is carried through when a device goes absent but stays listed", () => {
  const armed = Model.diffEvents([], [device({ percentage: 10, nativePath: "/a" })], {}, options)
  assert.equal(armed.events.length, 1)
  assert.equal(armed.events[0].kind, "low")

  const absent = Model.diffEvents([device({ percentage: 10, nativePath: "/a" })], [device({ isPresent: false, percentage: 10, nativePath: "/a" })], armed.armState, options)
  assert.equal(absent.events.length, 1)
  assert.equal(absent.events[0].kind, "disconnected")
  assert.equal(absent.armState["/a"].lowNotified, true)

  const returned = Model.diffEvents([device({ isPresent: false, percentage: 10, nativePath: "/a" })], [device({ percentage: 10, nativePath: "/a" })], absent.armState, options)
  assert.equal(returned.events.length, 0)
})

test("notification text names the device and the level", () => {
  const low = Model.notificationText({ kind: "low", model: "Jabra Evolve2 65", percentage: 18 })
  assert.equal(low.headline, "Battery low")
  assert.equal(low.body, "Jabra Evolve2 65 at 18%")

  const charged = Model.notificationText({ kind: "charged", model: "Sony WH-1000XM4", percentage: 100 })
  assert.equal(charged.headline, "Fully charged")
  assert.equal(charged.body, "Sony WH-1000XM4")

  const gone = Model.notificationText({ kind: "disconnected", model: "Arctis 7", percentage: 40 })
  assert.equal(gone.headline, "Device disconnected")
  assert.equal(gone.body, "Arctis 7")
})

test("the notification command passes every value as its own argument", () => {
  const command = Model.notificationCommand({ kind: "low", model: "Jabra; rm -rf /", percentage: 5 }, 0)
  assert.equal(command[0], "omarchy-notification-send")
  assert.equal(command.indexOf("--app-name") !== -1, true)
  assert.equal(command[command.indexOf("--app-name") + 1], "omajuice")
  assert.equal(command.indexOf("Jabra; rm -rf / at 5%") !== -1, true)
})

test("the headline and body are the final two arguments, so nothing can follow the device-controlled body", () => {
  const kinds = ["low", "charged", "disconnected"]
  const dangerousModels = ["--exec", "-i"]
  for (const kind of kinds) {
    for (const model of dangerousModels) {
      for (const replaceId of [0, 42]) {
        const event = { kind: kind, model: model, percentage: 5 }
        const text = Model.notificationText(event)
        const command = Model.notificationCommand(event, replaceId)
        assert.equal(command[command.length - 2], text.headline)
        assert.equal(command[command.length - 1], text.body)
      }
    }
  }
})

test("low battery is urgent, the other kinds are not", () => {
  const low = Model.notificationCommand({ kind: "low", model: "A", percentage: 5 }, 0)
  const charged = Model.notificationCommand({ kind: "charged", model: "A", percentage: 100 }, 0)
  assert.equal(low[low.indexOf("-u") + 1], "critical")
  assert.equal(charged[charged.indexOf("-u") + 1], "low")
})

test("a known id makes the notification replace the previous one", () => {
  const command = Model.notificationCommand({ kind: "low", model: "A", percentage: 5 }, 42)
  assert.equal(command[command.indexOf("-r") + 1], "42")
})

test("an unusable id is left out entirely", () => {
  for (const id of [0, -1, null, undefined, NaN]) {
    const command = Model.notificationCommand({ kind: "low", model: "A", percentage: 5 }, id)
    assert.equal(command.indexOf("-r"), -1)
  }
})
