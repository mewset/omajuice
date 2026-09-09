import QtQuick
import Quickshell
import qs.Ui
import qs.Commons
import "Model.js" as Model

// Bar item: an icon plus the lowest selected device's level, and the count
// when more than one device is selected. Left click toggles the panel.
//
// This widget never notifies. One instance exists per monitor, so
// notification logic here would fire once per screen; all notification
// state lives in Service.qml.
BarWidget {
  id: root
  moduleName: "io.github.mewset.omajuice"

  // Third-party widgets are not handed a `service` property directly - only
  // `bar`, `moduleName` and `settings` (see Bar.qml's injectProps). A plugin
  // reaches its own service singleton through bar.shell.serviceFor(id),
  // which is scoped so a plugin can only ever fetch the service matching its
  // own moduleName (shell.qml's pluginServiceFor/pluginOwnsTarget). The media
  // plugin's bar.shell.firstPartyServiceFor is the first-party equivalent of
  // this same call and is not available to third-party plugins like this one.
  readonly property var service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null

  readonly property var summary: service ? service.summary : Model.summarize([])
  readonly property bool hideWhenEmpty: setting("hideWhenEmpty", true) === true
  readonly property int lowBatteryThreshold: Number(setting("lowBatteryThreshold", 20))
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  // Shared between both orientations so charging state, the urgent
  // threshold and the font are decided in one place rather than twice.
  //
  // Nerd Font glyphs, not emoji: emoji are rendered by the colour emoji
  // font regardless of font.family, so they carry their own size and
  // baseline and stick out next to every other (Nerd Font) glyph in the
  // bar. U+F02CB is the headphones glyph, the same one the shell's own
  // audio plugin uses for headphones (Panel.qml's outputIcon, "isHeadphones"
  // branch). U+F0084 is the battery-charging glyph from the same Material
  // Design Nerd Font family.
  readonly property string deviceGlyph: summary.charging ? "\u{f0084}" : "\u{f02cb}"
  readonly property string barFontFamily: bar ? bar.fontFamily : Style.fontFamily
  readonly property color barForeground: bar ? bar.barForeground : Color.foreground
  readonly property color levelColor: summary.lowest >= 0 && summary.lowest <= lowBatteryThreshold
    ? (bar ? bar.urgent : Color.urgent)
    : barForeground

  // One row per line in a vertical bar: icon first, then the lowest level
  // (no "%" - it would push a 3-digit reading past 3 characters, and a
  // longer reading is exactly what the clock plugin's own vertical layout
  // shrinks the font for, by passing a reduced fontSize into OpticalGlyph
  // from its caller), then the count only when it says something the
  // level alone doesn't.
  readonly property var verticalRows: [
    { text: deviceGlyph, size: Style.bar.iconFont, color: barForeground },
    { text: String(summary.lowest), size: Style.font.body, color: levelColor, shown: summary.count > 0 },
    { text: "×" + summary.count, size: Style.font.body, color: levelColor, shown: summary.count > 1 }
  ]

  // The shell hands settings to widgets only, so the service is told here.
  // Every monitor pushes the same object, which is why applySettings must be
  // idempotent.
  onSettingsChanged: {
    if (service) service.applySettings(settings)
    injectPanel()
  }
  Component.onCompleted: if (service) service.applySettings(settings)

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (opened) close()
    else open()
  }

  // Forwarded so this widget can stand in for the panel as the bar's popout
  // identity: Bar.requestPopout prefers closeForPopoutSwitch over close, and
  // KeyboardPanel reads popoutSwitchClosing back off its owner (see the
  // clock plugin's BarWidget.qml for the same six lines and the same reason
  // - without them, switching panels still works through Bar.qml's close()
  // fallback, but loses the instant handoff and cross-fades instead).
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  // Hands the panel everything it needs to render and to anchor itself.
  // Called whenever any of those inputs change, not only once at load, so a
  // bar reconfiguration or a settings change reaches the already-loaded panel.
  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("service" in target) target.service = root.service
  }

  visible: !hideWhenEmpty || summary.count > 0
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  // `service` can flip from null to non-null after settings have already
  // arrived (pluginBarApiFor reassigns `.shell` on a cached api, and
  // createScopedPluginShell returns null before the manifest registers), so
  // onSettingsChanged alone can miss the window. Service.qml does not diff
  // or notify until its first applySettings, so a missed window means the
  // plugin stays silent for the rest of the session unless caught here too.
  onServiceChanged: {
    if (service) service.applySettings(settings)
    injectPanel()
  }

  MouseArea {
    id: button
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    implicitWidth: root.vertical ? root.barSize : row.implicitWidth + Style.space(8)
    // Horizontal: full bar thickness, like every other full-height widget
    // (e.g. the media plugin's BarWidget.qml), so this item's click target
    // and its open-panel indicator line up with neighbouring icons instead
    // of only spanning the text's own height. Vertical: the stacked rows
    // are what determines the item's length along the bar, and the slot's
    // width is pinned regardless, so column.implicitHeight is already right.
    implicitHeight: root.vertical ? column.implicitHeight : root.barSize
    onClicked: root.toggle()

    // Horizontal bar: icon and level side by side on one line.
    Row {
      id: row
      visible: !root.vertical
      anchors.centerIn: parent
      spacing: Style.space(4)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.deviceGlyph
        color: root.barForeground
        font.family: root.barFontFamily
        font.pixelSize: Style.bar.iconFont
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.summary.count > 0
        text: root.summary.count > 1
          ? root.summary.lowest + "% · " + root.summary.count
          : root.summary.lowest + "%"
        color: root.levelColor
        font.family: root.barFontFamily
        font.pixelSize: Style.font.body
      }
    }

    // Vertical bar: the slot is pinned to bar thickness (ModuleSlot in
    // Bar.qml), too narrow for the horizontal line, so icon and level stack
    // in icon-sized rows instead - the same answer the clock plugin gives
    // to a vertical bar.
    Column {
      id: column
      visible: root.vertical
      anchors.fill: parent

      Repeater {
        model: root.verticalRows

        OpticalGlyph {
          required property var modelData
          visible: modelData.shown !== false
          width: column.width
          height: Style.bar.iconSlot
          text: modelData.text
          fontFamily: root.barFontFamily
          fontSize: modelData.size
          color: modelData.color
        }
      }
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }
}
