# USB NVMe Drive Performance (RTL9210 enclosures)

**Problem:** external NVMe over USB-C in an RTL9210 enclosure (`0bda:9210`) runs slow under UAS (capped ~30 MB/s, or degrades over a transfer) and/or resets mid-use — `uas_eh_abort_handler` / `uas_eh_device_reset_handler` storms in `dmesg`, filesystem can drop to `emergency_ro`.

**Cause:** UAS (USB Attached SCSI) command queuing is unstable with RTL9210 bridge chips on Linux — it both throttles throughput and can overwhelm the bridge into abort/reset storms.

**Applied fix — force usb-storage (BOT) instead of UAS:**
```bash
# Blacklist UAS for this device
sudo bash -c 'echo "options usb-storage quirks=0bda:9210:u" > /etc/modprobe.d/disable-uas-realtek.conf'
# Rebuild initramfs so it takes effect on boot
sudo mkinitcpio -P
# Unplug and replug the drive
```

**Verify:**
```bash
lsusb -t | grep -A2 "Driver"   # should show "usb-storage", not "uas"
```
Throughput check: `sudo dd if=/dev/sda of=/dev/null bs=1M count=2000 status=progress` (replace `sda`).

**Tradeoff:** loses UAS command queuing (~5–10% slower random small I/O; sequential throughput unaffected — USB 3.2 Gen 2 ≈1,000 MB/s is the bottleneck either way). Stability gain is the main win.

**Undo:** `sudo rm /etc/modprobe.d/disable-uas-realtek.conf && sudo mkinitcpio -P`.

**Equivalent alternative (not applied):** kernel cmdline `usb-storage.quirks=0bda:9210:u` — GRUB: add to `GRUB_CMDLINE_LINUX_DEFAULT` in `/etc/default/grub`, then `sudo grub-mkconfig -o /boot/grub/grub.cfg`; Limine: add to `CMDLINE=`. Same result; the modprobe config is simpler to manage (and is what's applied here).

**If still slow after the UAS fix:** scheduler + USB power tuning can help —
```bash
echo none | sudo tee /sys/block/sda/queue/scheduler
echo on | sudo tee /sys/bus/usb/devices/2-5/power/control
```
Replace `sda`/`2-5` with your block device and USB path (`readlink -f /sys/block/sda/device`). Persist via a udev rule matching `0bda:9210` (scheduler=none, power/control=on), then `sudo udevadm control --reload-rules && sudo udevadm trigger`. If throughput is still bad: `iommu=soft amd_iommu=off`, a BIOS update, a different port/controller, or a non-RTL9210 enclosure (ASMedia ASM2364, JMicron).
