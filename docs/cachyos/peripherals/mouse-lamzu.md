# LAMZU Maya X Mouse

Configure via [Aurora web interface](https://www.lamzu.net/#/project/items). Need udev rules for dongle and direct USB.

**Get IDs:** `lsusb | grep -i LAMZU` (dongle and cable-connected mouse).

Create `/etc/udev/rules.d/99-lamzu-maya.rules` with rules for both devices. Example (adjust vendor/product/names):
- Dongle: `SUBSYSTEM=="input", ATTRS{id/vendor}=="373e", ATTRS{name}=="LAMZU LAMZU Maya X 8K Dongle", MODE="0666", GROUP="input", TAG+="uaccess"` (and Consumer/System/Keyboard variants).
- Mouse: `SUBSYSTEM=="input", ATTRS{id/vendor}=="373e", ATTRS{name}=="LAMZU LAMZU MAYA X", ...` (and variants).
- USB: `SUBSYSTEM=="usb", ATTRS{idVendor}=="373e", ATTRS{idProduct}=="001e", ...` and `001c`.
- hidraw: `KERNEL=="hidraw*", ATTRS{idVendor}=="373e", ATTRS{idProduct}=="001e", ...` and `001c`.

Then: `sudo udevadm control --reload-rules && sudo udevadm trigger`. Use Chromium-based browser for config site.
