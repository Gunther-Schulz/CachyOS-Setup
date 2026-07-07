# Sleep & Wake (Asus Laptop)

**BIOS patching via GRUB (S3):** Does **not** work — patching applies but S3 sleep still fails. Reference doc has SSDT/GRUB steps for completeness.

**Show sleep modes:** `cat /sys/power/mem_sleep`.

**Temporary:** `echo deep | sudo tee /sys/power/mem_sleep` (resets after reboot).

**Permanent:** systemd oneshot service that runs `echo deep > /sys/power/mem_sleep`, `WantedBy=multi-user.target`, `After=suspend.target`. Enable and start; verify with `cat /sys/power/mem_sleep`.

## Laptop wakes itself from suspend (spurious s2idle wake)

**Symptom:** suspends fine, then wakes on its own **minutes later** at irregular intervals (seen 3–70 min) — *not* a scheduled/RTC wake.

**Rule out the easy ones, then find the source** (no reboot needed):

```sh
cat /sys/class/rtc/rtc0/wakealarm                       # empty = nothing timed a wake
systemctl list-timers --all | grep -i wake              # no WakeSystem=true units
# which wakeup sources have actually fired (active_count):
for w in /sys/class/wakeup/wakeup*; do printf '%s\tactive=%s\n' "$(cat $w/name)" "$(cat $w/active_count)"; done | sort -t= -k2 -rn
# dominant ACPI firmware event:
grep -H . /sys/firmware/acpi/interrupts/sci /sys/firmware/acpi/interrupts/gpe07
```

**Cause (FA607PV):** the **Bluetooth controller** `0000:06:00.0` (hosts the AX210) stays `wakeup=enabled`, so BT-HID activity — an MX Master / MX Keys drifting on the desk, or the SMSL BT amp reconnecting — wakes the laptop, *even though* the AX210 device node is already `wakeup=disabled`. (The LAMZU 8K dongle is a **separate, already-handled** case: its own wakeup is disabled by `90-lamzu-no-wakeup.rules`, and it was *not* the culprit — the wakes happened with it unplugged.)

**Fix — disable wake on the Bluetooth controller** (persistent, alongside the LAMZU rule):

```sh
# test at runtime first (resets on reboot):
echo disabled | sudo tee /sys/bus/pci/devices/0000:06:00.0/power/wakeup
#   → suspend and confirm it stays asleep 30–60 min, then persist:
echo 'ACTION=="add", SUBSYSTEM=="pci", KERNEL=="0000:06:00.0", ATTR{power/wakeup}="disabled"' \
  | sudo tee /etc/udev/rules.d/91-bt-controller-no-wakeup.rules
sudo udevadm control --reload
```

**Trade-off:** you can no longer wake the laptop by touching the BT mouse/keyboard — use lid-open, the power button, or the built-in keyboard.

**If it still wakes**, the firmware **GPE** is the culprit instead (on this machine `gpe07` dominates the ACPI SCIs). Snapshot `cat /sys/firmware/acpi/interrupts/gpe07`; if it jumps across a spurious wake, mask it: `echo disable | sudo tee /sys/firmware/acpi/interrupts/gpe07` (reversible with `enable` — but watch that AC-adapter, lid, and thermal events still register, since a GPE can carry those).
