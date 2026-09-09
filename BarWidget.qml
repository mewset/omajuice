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
    implicitWidth: row.implicitWidth + Style.space(8)
    implicitHeight: row.implicitHeight
    onClicked: root.toggle()

    Row {
      id: row
      anchors.centerIn: parent
      spacing: Style.space(4)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: root.summary.charging ? "⚡" : "\u{1f3a7}"
        color: root.bar ? root.bar.barForeground : Color.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.fontFamily
        font.pixelSize: Style.bar.iconFont
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        visible: root.summary.count > 0
        text: root.summary.count > 1
          ? root.summary.lowest + "% · " + root.summary.count
          : root.summary.lowest + "%"
        color: root.summary.lowest >= 0 && root.summary.lowest <= root.lowBatteryThreshold
          ? (root.bar ? root.bar.urgent : Color.urgent)
          : (root.bar ? root.bar.barForeground : Color.foreground)
        font.family: root.bar ? root.bar.fontFamily : Style.fontFamily
        font.pixelSize: Style.font.body
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
