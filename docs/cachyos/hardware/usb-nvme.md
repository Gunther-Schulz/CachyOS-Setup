# USB NVMe Drive Performance

**Problem:** External NVMe over USB-C slower than expected (e.g. USB 3.2 Gen 2).

**Cause:** Aggressive USB power management and suboptimal I/O scheduler.

**Diagnosis:** Check scheduler (`cat /sys/block/sda/queue/scheduler` → prefer `none`), USB power (`cat /sys/bus/usb/devices/4-2/power/control` → prefer `on`), device path (`lsusb -t | grep -i "Mass Storage"`).

**Temporary test:**
```bash
echo none | sudo tee /sys/block/sda/queue/scheduler
echo on | sudo tee /sys/bus/usb/devices/4-2/power/control
```
Replace `sda` and `4-2` with your device.

**Permanent:** udev rules in `/etc/udev/rules.d/99-nvme-usb-performance.rules`. Example for Realtek RTL9210 (`0bda:9210`): disable USB power management for that vendor/product; set `queue/scheduler=none` and `queue/read_ahead_kb=1024` for matching `sd*`. Reload: `sudo udevadm control --reload-rules && sudo udevadm trigger`. Reconnect or reboot.

**Verify:** `sudo hdparm -tT /dev/sda` or real-world copy test.

**Progressive slowdown (RTL9210):** If speed degrades over time, try disabling UAS: add `usb-storage.quirks=0bda:9210:u` to kernel cmdline (Limine: `CMDLINE=...` in config; GRUB: `GRUB_CMDLINE_LINUX_DEFAULT=...`). Then `lsusb -t` should show `usb-storage` instead of `uas`. Untested.
