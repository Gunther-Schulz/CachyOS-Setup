# Sleep & Wake (Asus Laptop)

**BIOS patching via GRUB (S3):** Does **not** work — patching applies but S3 sleep still fails. Reference doc has SSDT/GRUB steps for completeness.

**Show sleep modes:** `cat /sys/power/mem_sleep`.

**Temporary:** `echo deep | sudo tee /sys/power/mem_sleep` (resets after reboot).

**Permanent:** systemd oneshot service that runs `echo deep > /sys/power/mem_sleep`, `WantedBy=multi-user.target`, `After=suspend.target`. Enable and start; verify with `cat /sys/power/mem_sleep`.

## LAMZU 8K dongle causes immediate (~1 s) re-wake

The **LAMZU Maya X 8K dongle** (USB `373e:001e`) was the only USB device left `power/wakeup=enabled`; its 8K-polling chatter re-woke the machine within ~1 s of suspend via ACPI SCI (`pm_wakeup_irq: 9`). The screen stays dark (GNOME locked) so it *looks* asleep, but the CPU is running and a keypress drops to the lock screen. Fix — persistent udev rule `/etc/udev/rules.d/90-lamzu-no-wakeup.rules`:
```
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="373e", ATTR{idProduct}=="001e", ATTR{power/wakeup}="disabled"
```
Then `sudo udevadm control --reload` + replug. Trade-off: the mouse no longer wakes the laptop (use keyboard/power button). Aside: GNOME's `sleep-inactive-ac-type` defaults to `'nothing'`, so on AC it never *auto*-suspends — set `'suspend'` if idle-suspend on AC is wanted.
