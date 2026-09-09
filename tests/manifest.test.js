const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const manifest = JSON.parse(
  fs.readFileSync(path.join(__dirname, "..", "manifest.json"), "utf8")
)

test("the manifest carries the permanent identity", () => {
  assert.equal(manifest.schemaVersion, 1)
  assert.equal(manifest.id, "io.github.mewset.omajuice")
  assert.equal(manifest.license, "MIT")
  assert.equal(typeof manifest.version, "string")
})

test("every declared kind has an entry point file that exists", () => {
  const entryFor = { "service": "service", "bar-widget": "barWidget" }
  for (const kind of manifest.kinds) {
    const key = entryFor[kind]
    assert.ok(key, `unexpected kind ${kind}`)
    const file = manifest.entryPoints[key]
    assert.ok(file, `no entry point for ${kind}`)
    assert.ok(
      fs.existsSync(path.join(__dirname, "..", file)),
      `${file} is missing`
    )
  }
})

test("every settings key has both a schema entry and a default", () => {
  const keys = manifest.barWidget.schema.map(entry => entry.key)
  assert.deepEqual(keys.sort(), [
    "hideWhenEmpty",
    "lowBatteryThreshold",
    "notifyDisconnect",
    "notifyFullyCharged",
    "notifyLowBattery",
    "showAllDevices"
  ])
  for (const entry of manifest.barWidget.schema) {
    assert.notEqual(
      manifest.barWidget.defaults[entry.key], undefined,
      `${entry.key} has no default`
    )
    assert.equal(manifest.barWidget.defaults[entry.key], entry.defaultValue)
  }
})
