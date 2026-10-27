import QtQuick
import QtQuick.Layouts
import qs.Ui
import qs.Commons
import "Model.js" as Model

// Device list opened from the bar widget: one row per selected device,
// ordered by level ascending (lowest first) since that is the device
// needing attention, plus a "show every external device" toggle. That
// toggle is real interactive content - not decoration - so this anchors
// through KeyboardPanel rather than PopupCard: every first-party plugin
// with a Panel.qml of this shape (bluetooth, power, tailscale, dropbox,
// audio, network, monitor, weather, clock, agents) uses KeyboardPanel once
// there is a control to click, and PopupCard stays reserved for the simpler
// popups a BarWidget builds inline for itself (Tray, the media plugin).
Panel {
  id: root
  moduleName: "io.github.mewset.omajuice"

  // BarWidget.qml owns the bar button and hands this panel the button to
  // anchor against, plus the widget instance the bar's popout coordinator
  // and click-target bookkeeping actually track.
  property var anchorItem: null
  property var hostWidget: null
  property var service: null

  onOpenedChanged: if (root.opened && root.service) root.service.refreshSoundcore()

  readonly property var barIdentity: hostWidget || root
  readonly property var devices: service ? service.devices : []
  readonly property bool showAllDevices: setting("showAllDevices", false) === true
  readonly property int lowBatteryThreshold: Number(setting("lowBatteryThreshold", 20))
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.fontFamily

  function stateLabel(device) {
    if (Number(device.state) === Model.DeviceState.Charging) return "Charging"
    if (Number(device.state) === Model.DeviceState.FullyCharged) return "Full"
    if (device.isPresent !== true) return "Absent"
    return device.connection
  }

  // Flips showAllDevices and writes the whole settings object back, not
  // just this one key: updateEntryInline (shell.qml) replaces the widget's
  // layout entry wholesale rather than merging, so sending only the changed
  // key would silently drop every other setting the user has on this
  // widget (e.g. hideWhenEmpty). Starting from root.settings - the object
  // this panel was actually handed - also means a setting still sitting at
  // its manifest default, and therefore absent from the layout entry, is
  // not resurrected as an explicit value here. Matches the pattern the
  // power plugin's togglePercentage uses for the same reason.
  function toggleShowAllDevices() {
    root.settings = Object.assign({}, root.settings, { showAllDevices: !root.showAllDevices })
    if (root.bar && root.bar.shell) root.bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  KeyboardPanel {
    id: popup
    anchorItem: root.anchorItem
    bar: root.bar
    owner: root.barIdentity
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(300))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    // KeyboardPanel primes layer-shell keyboard focus on open regardless of
    // whether the panel has anything worth navigating - see its own comment
    // on why Qt still needs an in-surface focus target before Escape (or any
    // other key) actually reaches a handler. Without one, focus is taken from
    // whatever the user was typing in and never given back. This panel has
    // exactly one control and no cursor to move between rows, so it wires
    // only the close and tab-switch signals every first-party panel wires -
    // not the arrow-key/activate cursor machinery those panels add on top
    // for navigating a list, which this panel has no use for.
    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ColumnLayout {
        id: column
        anchors.fill: parent
        spacing: Style.space(6)

        // Always present, not only in the empty state - a toggle that only
        // shows up when the list is empty would vanish the moment switching
        // it on brings devices into view, leaving no way to switch it back
        // off. This is a setting, not a list row, so it sits above the
        // separator rather than among the device rows below.
        RowLayout {
          id: settingsRow
          Layout.fillWidth: true
          spacing: Style.space(10)

          Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            text: "Show every external device"
          }

          ToggleSwitch {
            checked: root.showAllDevices
            foreground: root.foreground
            onToggled: root.toggleShowAllDevices()
          }
        }

        PanelSeparator {
          Layout.fillWidth: true
          foreground: root.foreground
        }

        Text {
          visible: root.devices.length === 0
          Layout.fillWidth: true
          wrapMode: Text.WordWrap
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          text: root.showAllDevices ? "No external device found." : "No headset found."
        }

        Repeater {
          model: root.devices

          ColumnLayout {
            id: deviceItem
            required property var modelData
            Layout.fillWidth: true
            spacing: Style.space(2)

            readonly property bool detailed: modelData.connection === "Bluetooth" && Model.isAudioDevice(modelData)
            readonly property string mac: detailed ? Model.macFromNativePath(modelData.nativePath) : ""
            readonly property var details: detailed && root.service
              ? Model.detailsFor(root.service.codecFor(modelData), root.service.soundcore[mac])
              : { codec: "", mode: "", modeClickable: false, batteries: "" }

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.space(10)

              Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                // The model comes from the device's own Bluetooth name, so a
                // peripheral could name itself "<img src=...>". AutoText would
                // render that as rich text and fetch the image on panel open.
                textFormat: Text.PlainText
                text: deviceItem.modelData.model
              }

              Text {
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                text: root.stateLabel(deviceItem.modelData)
              }

              Text {
                color: deviceItem.modelData.percentage <= root.lowBatteryThreshold ? root.urgent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                text: deviceItem.modelData.percentage + "%"
              }
            }

            RowLayout {
              visible: deviceItem.details.codec !== "" || deviceItem.details.mode !== ""
              Layout.fillWidth: true
              spacing: 0

              Text {
                visible: deviceItem.details.codec !== ""
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                textFormat: Text.PlainText
                text: deviceItem.details.codec
              }

              Text {
                visible: deviceItem.details.codec !== "" && deviceItem.details.mode !== ""
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                text: " \u00b7 "
              }

              Text {
                id: modeText
                visible: deviceItem.details.mode !== ""
                color: deviceItem.details.modeClickable && modeArea.containsMouse ? root.foreground : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.underline: deviceItem.details.modeClickable
                textFormat: Text.PlainText
                text: deviceItem.details.mode

                MouseArea {
                  id: modeArea
                  anchors.fill: parent
                  enabled: deviceItem.details.modeClickable
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.service.cycleMode(deviceItem.mac)
                }
              }
            }

            Text {
              visible: deviceItem.details.batteries !== ""
              Layout.fillWidth: true
              elide: Text.ElideRight
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              textFormat: Text.PlainText
              text: deviceItem.details.batteries
            }
          }
        }
      }
    }
  }
}
