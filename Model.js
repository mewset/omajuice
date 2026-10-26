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
    // Quickshell's UPowerDevice.percentage is a fraction from 0 to 1, not a
    // whole percentage, exactly like Omarchy's own battery plugin assumes
    // (see /usr/share/omarchy/shell/plugins/services/battery/BatteryModel.js,
    // `Math.round(Number(device.percentage || 0) * 100)`). Everything past
    // this boundary works in whole percentages, so the multiplication by 100
    // must stay here and must never be "simplified" away.
    percentage: Math.round(Number(input.percentage || 0) * 100),
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

// The bar already ships a laptop battery widget, and the mains supply has no
// battery to report, so both are dropped before anything else is considered.
function selectDevices(devices, showAllDevices) {
  var list = devices || []
  var out = []

  for (var i = 0; i < list.length; i++) {
    var candidate = list[i]
    if (candidate.isLaptopBattery === true) continue
    if (candidate.powerSupply === true) continue
    if (Number(candidate.type) === DeviceType.LinePower) continue
    if (showAllDevices !== true && !isAudioDevice(candidate)) continue
    out.push(candidate)
  }

  out.sort(function (left, right) {
    return Number(left.percentage) - Number(right.percentage)
  })

  return out
}

function summarize(devices) {
  var list = devices || []
  var usable = []
  var charging = false

  for (var i = 0; i < list.length; i++) {
    if (list[i].isPresent !== true) continue
    usable.push(list[i])
    if (Number(list[i].state) === DeviceState.Charging) charging = true
  }

  if (usable.length === 0) {
    return { count: 0, lowest: -1, charging: false, device: null }
  }

  var lowest = usable[0]
  for (var j = 1; j < usable.length; j++) {
    if (Number(usable[j].percentage) < Number(lowest.percentage)) lowest = usable[j]
  }

  return {
    count: usable.length,
    lowest: Number(lowest.percentage),
    charging: charging,
    device: lowest
  }
}

// A level oscillating on the boundary would notify on every tick without a
// margin, so the arm only resets once the device is meaningfully recovered.
var HYSTERESIS = 5

function defaultOptions() {
  return {
    threshold: 20,
    notifyLowBattery: true,
    notifyFullyCharged: true,
    notifyDisconnect: false
  }
}

function indexByKey(devices) {
  var index = {}
  var list = devices || []
  for (var i = 0; i < list.length; i++) index[list[i].key] = list[i]
  return index
}

function eventFor(kind, device) {
  return {
    kind: kind,
    key: device.key,
    model: device.model,
    percentage: Number(device.percentage)
  }
}

function diffEvents(previous, next, armState, options) {
  var settings = options || defaultOptions()
  var threshold = Number(settings.threshold)
  var before = indexByKey(previous)
  var after = next || []
  var previousArm = armState || {}
  var arm = {}
  var events = []

  for (var i = 0; i < after.length; i++) {
    var current = after[i]
    var earlier = before[current.key]
    var wasArmed = previousArm[current.key] ? previousArm[current.key].lowNotified === true : false
    var level = Number(current.percentage)
    var state = Number(current.state)

    if (current.isPresent !== true) {
      if (earlier && earlier.isPresent === true && settings.notifyDisconnect === true) {
        events.push(eventFor("disconnected", current))
      }
      arm[current.key] = { lowNotified: wasArmed }
      continue
    }

    // A level of zero is missing data, not an emergency: some devices
    // report nothing useful until a media profile is active (see the
    // spec's risk section), and summarize() already excludes a zero-level
    // ABSENT device from the summary for the same reason. This extends
    // that to the low-battery branch. level > 0 is deliberately excluded
    // from arming too - a device stuck at zero must not become armed as a
    // side effect, or it would stay silent forever once it starts
    // reporting real numbers and actually drops below the threshold.
    if (state !== DeviceState.Charging && level > 0 && level <= threshold) {
      if (!wasArmed) {
        wasArmed = true
        if (settings.notifyLowBattery === true) events.push(eventFor("low", current))
      }
    } else if (level > threshold + HYSTERESIS) {
      wasArmed = false
    }

    // Only a transition counts, so a shell restart with a device already full
    // stays quiet.
    if (settings.notifyFullyCharged === true && state === DeviceState.FullyCharged
        && earlier && Number(earlier.state) !== DeviceState.FullyCharged) {
      events.push(eventFor("charged", current))
    }

    arm[current.key] = { lowNotified: wasArmed }
  }

  if (settings.notifyDisconnect === true) {
    var stillHere = indexByKey(after)
    var was = previous || []
    for (var j = 0; j < was.length; j++) {
      if (!stillHere[was[j].key]) events.push(eventFor("disconnected", was[j]))
    }
  }

  return { events: events, armState: arm }
}

// A Bluetooth device is identified by its MAC across BlueZ, PipeWire and
// openscq30, each of which spells it differently. Everything is reduced to
// 12 lowercase hex characters and only turned back into colons for display
// and for the openscq30 command line.
function normalizeMac(text) {
  if (typeof text !== "string") return ""
  var hex = text.replace(/[^0-9a-fA-F]/g, "").toLowerCase()
  return hex.length === 12 ? hex : ""
}

// Only the part after "dev_" is the MAC: "bluez" and "hci" contain hex
// letters of their own.
function macFromNativePath(nativePath) {
  if (typeof nativePath !== "string") return ""
  var match = /\/org\/bluez\/[^\/]+\/dev_([^\/]*)$/.exec(nativePath)
  return match ? normalizeMac(match[1]) : ""
}

function colonMac(mac) {
  var hex = normalizeMac(mac)
  if (hex === "") return ""
  return hex.match(/.{2}/g).join(":").toUpperCase()
}

var SINK_PREFIX = "bluez_output."

function sinkNameMatchesMac(nodeName, mac) {
  var wanted = normalizeMac(mac)
  if (wanted === "" || typeof nodeName !== "string") return false
  if (nodeName.indexOf(SINK_PREFIX) !== 0) return false
  var hex = nodeName.slice(SINK_PREFIX.length).replace(/[^0-9a-fA-F]/g, "").toLowerCase()
  return hex.indexOf(wanted) !== -1
}

// PipeWire's api.bluez5.codec values.
var CODEC_LABELS = {
  sbc: "SBC",
  sbc_xq: "SBC-XQ",
  aac: "AAC",
  aac_eld: "AAC-ELD",
  aptx: "aptX",
  aptx_hd: "aptX HD",
  aptx_ll: "aptX LL",
  aptx_ll_duplex: "aptX LL",
  ldac: "LDAC",
  lc3: "LC3",
  lc3plus_h3: "LC3plus",
  faststream: "FastStream",
  faststream_duplex: "FastStream",
  opus_05: "Opus",
  msbc: "mSBC",
  cvsd: "CVSD"
}

function codecLabel(raw) {
  if (typeof raw !== "string" || raw === "") return ""
  var key = raw.toLowerCase()
  return CODEC_LABELS.hasOwnProperty(key) ? CODEC_LABELS[key] : raw.toUpperCase()
}

// openscq30 talks to Soundcore headsets over their own channel. The command
// below is the only shell string in the plugin; it interpolates nothing and
// exits 127 when the tool is not installed.
var OPENSCQ30_PAIRED_COMMAND = [
  "sh", "-c",
  "command -v openscq30 >/dev/null 2>&1 && exec openscq30 paired-devices list --json"
]

function parseJson(text) {
  try {
    return JSON.parse(text)
  } catch (error) {
    return undefined
  }
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function parsePairedDevices(text) {
  var list = parseJson(text)
  if (!Array.isArray(list)) return []
  var macs = []
  for (var i = 0; i < list.length; i++) {
    var entry = list[i]
    if (!isPlainObject(entry) || entry.isDemo === true) continue
    var mac = normalizeMac(entry.macAddress)
    if (mac !== "") macs.push(mac)
  }
  return macs
}

function deviceCommand(mac, rest) {
  var colons = colonMac(mac)
  if (colons === "") return null
  return ["openscq30", "device", "-a", colons].concat(rest)
}

function settingIdsCommand(mac) {
  return deviceCommand(mac, ["list-settings", "--no-categories", "--json"])
}

function parseSettingIds(text) {
  var settings = parseJson(text)
  return isPlainObject(settings) ? Object.keys(settings) : null
}

var SOUNDCORE_READ_IDS = [
  "ambientSoundMode", "batteryLevelLeft", "batteryLevelRight",
  "caseBatteryLevel", "twsStatus", "hostDevice"
]

function readCommand(mac, availableIds) {
  var rest = ["setting"]
  var wanted = 0
  for (var i = 0; i < SOUNDCORE_READ_IDS.length; i++) {
    if ((availableIds || []).indexOf(SOUNDCORE_READ_IDS[i]) === -1) continue
    rest.push("--get", SOUNDCORE_READ_IDS[i])
    wanted++
  }
  if (wanted === 0) return null
  rest.push("--json")
  return deviceCommand(mac, rest)
}

function parseSettingValues(text) {
  var list = parseJson(text)
  if (!Array.isArray(list) || list.length === 0) return null
  var values = {}
  for (var i = 0; i < list.length; i++) {
    var entry = list[i]
    if (!isPlainObject(entry) || typeof entry.settingId !== "string" || !isPlainObject(entry.value)) continue
    values[entry.settingId] = entry.value.value
  }
  return values
}

var AMBIENT_MODES = ["NoiseCanceling", "Transparency", "Normal"]

function nextAmbientMode(current) {
  var index = AMBIENT_MODES.indexOf(current)
  return index === -1 ? AMBIENT_MODES[0] : AMBIENT_MODES[(index + 1) % AMBIENT_MODES.length]
}

function setModeCommand(mac, mode) {
  if (AMBIENT_MODES.indexOf(mode) === -1) return null
  return deviceCommand(mac, [
    "setting", "--set", "ambientSoundMode=" + mode, "--get", "ambientSoundMode", "--json"
  ])
}

// Battery levels come as "n/5".
function levelFromFifths(text) {
  var match = /^([0-5])\/5$/.exec(typeof text === "string" ? text : "")
  return match ? Number(match[1]) * 20 : -1
}

var MODE_LABELS = {
  NoiseCanceling: "Noise cancelling",
  Transparency: "Transparency",
  Normal: "Normal"
}

var UNAVAILABLE_LABEL = "Mode unavailable"

function batteryParts(values) {
  var parts = []
  var apart = values.twsStatus === "Disconnected"
      && (values.hostDevice === "Left" || values.hostDevice === "Right")

  var left = levelFromFifths(values.batteryLevelLeft)
  var right = levelFromFifths(values.batteryLevelRight)
  var caseLevel = levelFromFifths(values.caseBatteryLevel)

  if (left >= 0 && !(apart && values.hostDevice !== "Left")) parts.push("L " + left + "%")
  if (right >= 0 && !(apart && values.hostDevice !== "Right")) parts.push("R " + right + "%")
  if (caseLevel >= 0 && !apart) parts.push("Case " + caseLevel + "%")

  return parts.join(" · ")
}

// soundcore is null for a device openscq30 does not manage, otherwise
// { status: "loading" | "loaded" | "switching" | "unavailable", values }.
function detailsFor(rawCodec, soundcore) {
  var details = { codec: codecLabel(rawCodec), mode: "", modeClickable: false, batteries: "" }
  if (!soundcore) return details

  if (soundcore.status === "unavailable") {
    details.mode = UNAVAILABLE_LABEL
    return details
  }

  var values = soundcore.values
  if (!values) return details

  var label = MODE_LABELS.hasOwnProperty(values.ambientSoundMode) ? MODE_LABELS[values.ambientSoundMode] : ""
  details.mode = label
  details.modeClickable = soundcore.status === "loaded" && label !== ""
  details.batteries = batteryParts(values)
  return details
}

var APP_NAME = "omajuice"

function notificationText(event) {
  if (event.kind === "charged") {
    return { headline: "Fully charged", body: String(event.model) }
  }
  if (event.kind === "disconnected") {
    return { headline: "Device disconnected", body: String(event.model) }
  }
  return {
    headline: "Battery low",
    body: String(event.model) + " at " + String(event.percentage) + "%"
  }
}

function notificationIcon(event) {
  if (event.kind === "charged") return "battery-full-charged"
  if (event.kind === "disconnected") return "audio-headset"
  return "battery-caution"
}

// Every value is its own array element. Nothing is ever assembled into a shell
// string, so a device that names itself after a command cannot run one.
//
// All flags come before the two positionals (headline, then body), and body
// is always last. omarchy-notification-send takes its headline and an
// optional description as the first one or two positionals that are not a
// recognized flag, then treats a trailing --exec as consuming the rest of
// the line as a click command. body is device-controlled text (a Bluetooth
// device's advertised model name), so if it were followed by more argv a
// device could name itself a flag, or "--exec ...", and hijack that tail.
// Putting body last means there is nothing after it left to hijack: a body
// that happens to equal a flag can at worst make the description slot go
// missing or the send fail, never redirect a later flag or arm a click
// command.
function notificationCommand(event, replaceId) {
  var text = notificationText(event)
  var command = [
    "omarchy-notification-send",
    "--app-name", APP_NAME,
    "-u", event.kind === "low" ? "critical" : "low",
    "-i", notificationIcon(event),
    "-p"
  ]

  var id = Number(replaceId)
  if (isFinite(id) && id > 0) command.push("-r", String(id))

  command.push(text.headline, text.body)

  return command
}

if (typeof module !== "undefined") {
  module.exports = {
    DeviceType: DeviceType,
    DeviceState: DeviceState,
    connectionFor: connectionFor,
    toDevice: toDevice,
    KEYWORDS: KEYWORDS,
    matchesKeyword: matchesKeyword,
    isAudioDevice: isAudioDevice,
    selectDevices: selectDevices,
    summarize: summarize,
    HYSTERESIS: HYSTERESIS,
    defaultOptions: defaultOptions,
    diffEvents: diffEvents,
    APP_NAME: APP_NAME,
    notificationText: notificationText,
    notificationIcon: notificationIcon,
    notificationCommand: notificationCommand,
    normalizeMac: normalizeMac,
    macFromNativePath: macFromNativePath,
    colonMac: colonMac,
    sinkNameMatchesMac: sinkNameMatchesMac,
    CODEC_LABELS: CODEC_LABELS,
    codecLabel: codecLabel,
    OPENSCQ30_PAIRED_COMMAND: OPENSCQ30_PAIRED_COMMAND,
    parsePairedDevices: parsePairedDevices,
    settingIdsCommand: settingIdsCommand,
    parseSettingIds: parseSettingIds,
    SOUNDCORE_READ_IDS: SOUNDCORE_READ_IDS,
    readCommand: readCommand,
    parseSettingValues: parseSettingValues,
    AMBIENT_MODES: AMBIENT_MODES,
    nextAmbientMode: nextAmbientMode,
    setModeCommand: setModeCommand,
    levelFromFifths: levelFromFifths,
    MODE_LABELS: MODE_LABELS,
    UNAVAILABLE_LABEL: UNAVAILABLE_LABEL,
    detailsFor: detailsFor
  }
}
