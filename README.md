# omajuice

Headset battery in the Omarchy bar. Level, charge state and connection type for
every wireless or USB headset UPower knows about, a panel listing them all, and
notifications for low battery, charge completion and disconnect.

No helper process, no daemon, no compiled dependency. The plugin reads UPower
through Quickshell directly.

## Requirements

Omarchy 4 or later, with plugin support.

Known gap: under a third-party bar that replaces Omarchy's own, the shell's
service lookup returns null and the widget renders as an invisible empty item.
Nothing breaks and no error appears, but there is also nothing to see or
click.

## Install

```bash
omarchy plugin add https://github.com/mewset/omajuice.git --enable
```

Add the widget to the bar from `Setup > Plugins`.

## Settings

| Setting | Default | Effect |
|---|---|---|
| Show every external device | Off | Lists mice, keyboards and controllers too |
| Low battery threshold | 20% | When the low battery notification fires |
| Notify on low battery | On | |
| Notify when fully charged | On | |
| Notify on disconnect | Off | Bluetooth devices drop out on every suspend |
| Hide when no device is found | On | Removes the bar item when nothing matches |

Changing a setting never itself counts as a device event, so it never
triggers a notification. One consequence: raising the threshold, or turning
on "Show every external device", can mark a device that is already below the
new threshold as already notified, without ever notifying you about it. That
device then stays quiet until its level rises back above the threshold by a
few points and drops again.

## How devices are matched

UPower reports a device type. Headset, headphones, speakers and other audio
types match immediately. Bluetooth devices frequently report no useful type at
all, so those fall back to a keyword list covering the common headset vendors
and model prefixes. The laptop battery and the mains supply are always
excluded, because the bar already reports those.

Turn on `Show every external device` if your headset is not recognised, and
open an issue with the device name so the keyword list can be extended.

## Development

```bash
node --test tests/
```

`Model.js` holds all logic and imports nothing from QML, so the whole test
suite runs without a shell.

## Licence

MIT
