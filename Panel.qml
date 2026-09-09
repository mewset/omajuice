import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Ui
import qs.Commons
import "Model.js" as Model

// Device list opened from the bar widget: one row per selected device,
// ordered by level ascending (lowest first) since that is the device
// needing attention. An informational popup, not an interactive one - no
// connect/forget actions - so it anchors through PopupCard rather than
// KeyboardPanel, matching the media plugin's own popup.
Panel {
  id: root
  moduleName: "io.github.mewset.omajuice"

  // BarWidget.qml owns the bar button and hands this panel the button to
  // anchor against, plus the widget instance the bar's popout coordinator
  // and click-target bookkeeping actually track.
  property var anchorItem: null
  property var hostWidget: null
  property var service: null

  readonly property var barIdentity: hostWidget || root
  readonly property var devices: service ? service.devices : []
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

  PopupCard {
    id: popup
    anchorItem: root.anchorItem
    bar: root.bar
    owner: root.barIdentity
    open: root.opened
    contentWidth: popup.fittedContentWidth(Style.space(300))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    ColumnLayout {
      id: column
      anchors.fill: parent
      spacing: Style.space(6)

      Text {
        visible: root.devices.length === 0
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        text: "No headset found. Turn on “Show every external device” in the widget settings to list everything UPower reports."
      }

      Repeater {
        model: root.devices

        RowLayout {
          id: deviceRow
          required property var modelData
          Layout.fillWidth: true
          spacing: Style.space(10)

          Text {
            Layout.fillWidth: true
            elide: Text.ElideRight
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            text: deviceRow.modelData.model
          }

          Text {
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            text: root.stateLabel(deviceRow.modelData)
          }

          Text {
            color: deviceRow.modelData.percentage <= root.lowBatteryThreshold ? root.urgent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            text: deviceRow.modelData.percentage + "%"
          }
        }
      }
    }
  }
}
