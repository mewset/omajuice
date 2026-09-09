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
