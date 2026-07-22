# Sleep & Wake (Asus Laptop)

**BIOS patching via GRUB (S3):** Does **not** work — patching applies but S3 sleep still fails. Reference doc has SSDT/GRUB steps for completeness.

**Show sleep modes:** `cat /sys/power/mem_sleep`.

**Temporary:** `echo deep | sudo tee /sys/power/mem_sleep` (resets after reboot).

**Permanent:** systemd oneshot service that runs `echo deep > /sys/power/mem_sleep`, `WantedBy=multi-user.target`, `After=suspend.target`. Enable and start; verify with `cat /sys/power/mem_sleep`.

## Lid close — keep running on AC, suspend on battery

Default `HandleLidSwitch=suspend` applies on AC too, so closing the lid killed long-running work while plugged in. Applied — `/etc/systemd/logind.conf.d/10-no-lid-suspend.conf`:
```ini
[Login]
HandleLidSwitch=suspend
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
```

**Precedence** (`man 5 logind.conf`): docked *or more than one display connected* → `…Docked=`; else on external power → `…ExternalPower=`; else → `HandleLidSwitch=`. So `HandleLidSwitch=` is effectively the battery-only case once the other two are set — leaving `…ExternalPower=` empty makes it fall back to `HandleLidSwitch=`, which is why the AC case must be spelled out.

Result: **AC → keeps running. Battery → suspends. Docked/external display → keeps running** (wins even on battery).

**Apply:** `sudo systemctl reload systemd-logind` — takes effect immediately, no re-login or reboot (confirmed on systemd 261).
**Verify:** `busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager HandleLidSwitch` (likewise `…ExternalPower`, `…Docked`).
**Undo:** `sudo rm /etc/systemd/logind.conf.d/10-no-lid-suspend.conf && sudo systemctl reload systemd-logind`.

**The internal panel goes dark regardless** — mutter disables the built-in output on lid close and moves windows to the external monitor. That's display handling, not suspend; independent of these settings.

**GNOME bypasses logind when an external monitor is attached:** `gsd-power` takes a `handle-lid-switch` inhibitor ("External monitor attached"), so logind's action is skipped entirely — check with `systemd-inhibit --list | grep -i lid`. Same outcome here, since `…Docked=ignore` already covers that case. Don't rely on the inhibitor alone: it disappears when the monitor is unplugged.

**Separate from the idle timer.** Lid state and inactivity are two different suspend triggers; a closed laptop produces no input, so an idle timer will suspend it anyway if left on. Current values — AC `'nothing'` (GNOME default), battery `'suspend'`:
```bash
gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type
gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-battery-type
```

## LAMZU 8K dongle causes immediate (~1 s) re-wake

The **LAMZU Maya X 8K dongle** (USB `373e:001e`) was the only USB device left `power/wakeup=enabled`; its 8K-polling chatter re-woke the machine within ~1 s of suspend via ACPI SCI (`pm_wakeup_irq: 9`). The screen stays dark (GNOME locked) so it *looks* asleep, but the CPU is running and a keypress drops to the lock screen. Fix — persistent udev rule `/etc/udev/rules.d/90-lamzu-no-wakeup.rules`:
```
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="373e", ATTR{idProduct}=="001e", ATTR{power/wakeup}="disabled"
```
Then `sudo udevadm control --reload` + replug. Trade-off: the mouse no longer wakes the laptop (use keyboard/power button). Aside: GNOME's `sleep-inactive-ac-type` defaults to `'nothing'`, so on AC it never *auto*-suspends — set `'suspend'` if idle-suspend on AC is wanted.
