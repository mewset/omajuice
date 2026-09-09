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
