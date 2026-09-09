// Pure logic for omajuice. Loaded by QML as `import "Model.js" as Model` and
// by the tests with require, so it must stay free of QML imports and of ES
// module syntax.

var DeviceType = {
  Unknown: 0,
  LinePower: 1,
  Battery: 2,
  Ups: 3,
  Monitor: 4,
  Mouse: 5,
  Keyboard: 6,
  Pda: 7,
  Phone: 8,
  MediaPlayer: 9,
  Tablet: 10,
  Computer: 11,
  GamingInput: 12,
  Pen: 13,
  Touchpad: 14,
  Modem: 15,
  Network: 16,
  Headset: 17,
  Speakers: 18,
  Headphones: 19,
  Video: 20,
  OtherAudio: 21,
  RemoteControl: 22,
  Printer: 23,
  Scanner: 24,
  Camera: 25,
  Wearable: 26,
  Toy: 27,
  BluetoothGeneric: 28
}

var DeviceState = {
  Unknown: 0,
  Charging: 1,
  Discharging: 2,
  Empty: 3,
  FullyCharged: 4,
  PendingCharge: 5,
  PendingDischarge: 6
}

function connectionFor(nativePath) {
  var path = String(nativePath || "").toLowerCase()
  if (path === "") return "Unknown"
  if (path.indexOf("usb") !== -1) return "USB"
  return "Bluetooth"
}

function toDevice(source) {
  var input = source || {}
  var nativePath = String(input.nativePath || "")
  var model = String(input.model || "")
  var name = model !== "" ? model : "Unknown device"

  return {
    key: nativePath !== "" ? nativePath : name,
    model: name,
    type: Number(input.type || 0),
    percentage: Math.round(Number(input.percentage || 0)),
    state: Number(input.state || 0),
    isPresent: input.isPresent === true,
    isLaptopBattery: input.isLaptopBattery === true,
    powerSupply: input.powerSupply === true,
    nativePath: nativePath,
    connection: connectionFor(nativePath)
  }
}

// Ported from HeadsetManager.cpp in the HeadsetStatus project. Deliberately
// vendor-broad: a false positive shows one extra battery level, a false
// negative hides the device the plugin was installed for.
var KEYWORDS = [
  "headset", "headphone", "earphone", "earbud",
  "jabra", "bose", "sony", "sennheiser", "jbl", "beats",
  "hyperx", "steelseries", "razer", "logitech", "corsair",
  "plantronics", "poly", "audio-technica", "beyerdynamic",
  "akg", "skullcandy", "anker", "soundcore", "airpods",
  "galaxy buds", "pixel buds", "surface headphones",
  "wh-", "wf-", "qc", "quietcomfort", "evolve"
]

// UPower knows these are audio devices, so no guessing is needed.
var AUDIO_TYPES = [
  DeviceType.Headset,
  DeviceType.Headphones,
  DeviceType.Speakers,
  DeviceType.OtherAudio
]

// UPower has told us nothing useful, which is the common case for Bluetooth.
var AMBIGUOUS_TYPES = [DeviceType.Unknown, DeviceType.BluetoothGeneric]

function matchesKeyword(text) {
  var haystack = String(text || "").toLowerCase()
  if (haystack === "") return false
  for (var i = 0; i < KEYWORDS.length; i++) {
    if (haystack.indexOf(KEYWORDS[i]) !== -1) return true
  }
  return false
}

function isAudioDevice(device) {
  var type = Number(device.type)
  if (AUDIO_TYPES.indexOf(type) !== -1) return true
  if (AMBIGUOUS_TYPES.indexOf(type) === -1) return false
  return matchesKeyword(device.model) || matchesKeyword(device.nativePath)
}

if (typeof module !== "undefined") {
  module.exports = {
    DeviceType: DeviceType,
    DeviceState: DeviceState,
    connectionFor: connectionFor,
    toDevice: toDevice,
    KEYWORDS: KEYWORDS,
    matchesKeyword: matchesKeyword,
    isAudioDevice: isAudioDevice
  }
}
