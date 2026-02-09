# USB NVMe Drive Performance

**Problem:** External NVMe over USB-C slower than expected (e.g. USB 3.2 Gen 2), or stuck at ~30 MB/s even with 10 Gbps link.

**Causes:** (1) RTL9210 enclosures often run slowly with **UAS** on Linux (~30 MB/s). (2) Aggressive USB power management. (3) Suboptimal I/O scheduler.

**Diagnosis:**
- Link speed: `lsusb -t` → Mass Storage should show `10000M` or `5000M`, not `480M`.
- Which device is slow: `readlink -f /sys/block/sda/device` (and sdb) → note `usb2/2-5` vs `usb2/2-1`; test with `sudo dd if=/dev/sda of=/dev/null bs=1M count=2000 status=progress` (and sdb). If **both** RTL9210 devices are ~30 MB/s, UAS is the likely cause.
- Scheduler: `cat /sys/block/sda/queue/scheduler` → prefer `none`.
- USB power: `cat /sys/bus/usb/devices/2-5/power/control` → prefer `on`.

**Fix 1 – Disable UAS for RTL9210 (try this if both drives are ~30 MB/s):**

UAS with RTL9210 (0bda:9210) can cap throughput at ~30 MB/s on Linux. Forcing the older **usb-storage** (BOT) driver often restores full speed.

- **Kernel cmdline** (persistent): Add `usb-storage.quirks=0bda:9210:u` to your bootloader.
  - **GRUB:** Edit `/etc/default/grub`, in `GRUB_CMDLINE_LINUX_DEFAULT` add `usb-storage.quirks=0bda:9210:u`, then `sudo grub-mkconfig -o /boot/grub/grub.cfg`.
  - **Limine:** In your config set `CMDLINE=... usb-storage.quirks=0bda:9210:u`.
- Reboot. After boot, `lsusb -t` should show **`usb-storage`** (not `uas`) for the RTL9210 drives.
- Re-test: `sudo dd if=/dev/sda of=/dev/null bs=1M count=2000 status=progress`.

**Fix 2 – Scheduler and power (if still slow or no UAS change):**

Temporary:
```bash
echo none | sudo tee /sys/block/sda/queue/scheduler
echo on | sudo tee /sys/bus/usb/devices/2-5/power/control
```
Replace `sda` and `2-5` with your block device and USB path (`readlink -f /sys/block/sda/device` to find path).

Permanent: udev rules in `/etc/udev/rules.d/99-nvme-usb-performance.rules` for `0bda:9210` (disable USB power for that vendor/product; set `queue/scheduler=none`, `queue/read_ahead_kb=1024`). Then `sudo udevadm control --reload-rules && sudo udevadm trigger`, reconnect or reboot.

**Verify:** `sudo hdparm -tT /dev/sda` or `sudo dd if=/dev/sda of=/dev/null bs=1M count=2000 status=progress`.

---

**Progressive speed degradation (UNTESTED):** Transfer starts fast (400–500 MB/s) then degrades to 15–30 MB/s over time; reconnecting temporarily restores speed. Realtek RTL9210 + Linux UAS can cause this. Try the UAS quirk above (`usb-storage.quirks=0bda:9210:u`); verify with `lsusb -t` that driver is `usb-storage` not `uas`. May slightly reduce peak speed but can stabilize sustained transfers.

**If still slow or degrading:** Disable IOMMU (`iommu=soft amd_iommu=off` in kernel cmdline); update motherboard BIOS; try different USB ports/controllers; consider non-RTL9210 enclosure (e.g. ASMedia ASM2364, JMicron).
