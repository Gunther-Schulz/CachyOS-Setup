# LAMZU Maya X Mouse

**Machine:** Both.

Configure via [Aurora web interface](https://www.lamzu.net/#/project/items) — it runs over **WebHID in a Chromium browser**, so it needs udev permissions on the dongle + direct USB. The mouse *works* without these rules; you just can't reconfigure it (DPI/polling/RGB/firmware). Deploy on **every machine you configure the mouse from** (currently only on the desktop — add to the laptop too).

**Get IDs:** `lsusb | grep -i LAMZU` — run with dongle only, then with mouse connected via USB. Example: dongle `373e:001e`, mouse `373e:001c`. Give permission to both for firmware updates.

Create `/etc/udev/rules.d/99-lamzu-maya.rules`:

```
# LAMZU Maya X Mouse - Dongle
SUBSYSTEM=="input", ATTRS{id/vendor}=="373e", ATTRS{name}=="LAMZU LAMZU Maya X 8K Dongle", MODE="0666", GROUP="input", TAG+="uaccess"
SUBSYSTEM=="input", ATTRS{name}=="LAMZU LAMZU Maya X 8K Dongle Consumer Control", MODE="0666", GROUP="input", TAG+="uaccess"
SUBSYSTEM=="input", ATTRS{name}=="LAMZU LAMZU Maya X 8K Dongle System Control", MODE="0666", GROUP="input", TAG+="uaccess"
SUBSYSTEM=="input", ATTRS{name}=="LAMZU LAMZU Maya X 8K Dongle Keyboard", MODE="0666", GROUP="input", TAG+="uaccess"

# LAMZU Maya X Mouse - Direct Device
SUBSYSTEM=="input", ATTRS{id/vendor}=="373e", ATTRS{name}=="LAMZU LAMZU MAYA X", MODE="0666", GROUP="input", TAG+="uaccess"
SUBSYSTEM=="input", ATTRS{name}=="LAMZU LAMZU MAYA X Consumer Control", MODE="0666", GROUP="input", TAG+="uaccess"
SUBSYSTEM=="input", ATTRS{name}=="LAMZU LAMZU MAYA X System Control", MODE="0666", GROUP="input", TAG+="uaccess"
SUBSYSTEM=="input", ATTRS{name}=="LAMZU LAMZU MAYA X Keyboard", MODE="0666", GROUP="input", TAG+="uaccess"

# USB device rules for both dongle and mouse
SUBSYSTEM=="usb", ATTRS{idVendor}=="373e", ATTRS{idProduct}=="001e", MODE="0666", GROUP="input", TAG+="uaccess"
SUBSYSTEM=="usb", ATTRS{idVendor}=="373e", ATTRS{idProduct}=="001c", MODE="0666", GROUP="input", TAG+="uaccess"
KERNEL=="hidraw*", ATTRS{idVendor}=="373e", ATTRS{idProduct}=="001e", MODE="0666", GROUP="input", TAG+="uaccess"
KERNEL=="hidraw*", ATTRS{idVendor}=="373e", ATTRS{idProduct}=="001c", MODE="0666", GROUP="input", TAG+="uaccess"
```

Then: `sudo udevadm control --reload-rules && sudo udevadm trigger`. Use a Chromium-based browser for the config site.
