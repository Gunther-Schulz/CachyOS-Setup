# Sleep / Wake Issues

## spd5118 (DDR5 temp sensor) blocks suspend

**Symptom:** Suspend fails and system gets stuck. Logs show:

```
spd5118 8-0051: PM: dpm_run_callback(): spd5118_suspend [spd5118] returns -6
spd5118 8-0051: PM: failed to suspend async: error -6
PM: Some devices failed to suspend, or early wake event detected
```

The `spd5118` driver (DDR5 SPD hub temperature sensor) fails to suspend because the SMBus
device becomes inaccessible during the transition. After the failed S3 attempt, the system
falls back to s2idle which can also hang — especially if the NVIDIA GPU's GSP firmware
heartbeat has already timed out from the aborted suspend.

**Fix:** Unload the module before sleep and reload after wake via a systemd sleep hook:

```bash
sudo tee /usr/lib/systemd/system-sleep/spd5118.sh << 'EOF'
#!/bin/bash
case $1 in
  pre) modprobe -r spd5118 ;;
  post) modprobe spd5118 ;;
esac
EOF
sudo chmod +x /usr/lib/systemd/system-sleep/spd5118.sh
```

This preserves DDR5 temperature monitoring while awake. To blacklist entirely instead:

```
echo "blacklist spd5118" | sudo tee /etc/modprobe.d/spd5118-blacklist.conf
```

**Date discovered:** 2026-03-15

---

## asus_wmi / eeepc_wmi — useless on desktop, blacklisted

**Symptom:** Boot log shows:

```
asus_wmi: failed to register LPS0 sleep handler in asus-wmi
asus_wmi: Initialization: 0x0
asus_wmi: BIOS WMI version: 0.0
asus_wmi: SFUN value: 0x0
eeepc-wmi eeepc-wmi: Detected AsusMbSwInterface, not ASUSWMI, use DSTS
```

**Cause:** ASUS reuses the same WMI GUID across all products (laptops, desktops, netbooks).
The `eeepc_wmi` driver matches on that GUID and auto-loads, even though its features
(backlight, wireless toggle, hotkeys) are laptop-only. On the B850-G desktop board:

- `BIOS WMI version: 0.0` — no WMI spec implemented
- `SFUN value: 0x0` — zero supported features
- LPS0 registration fails because S0ix/Modern Standby doesn't exist on AM5 desktops — S3 (`deep`) is the correct sleep mode

The driver does nothing functional. `nct6775` + `k10temp` handle all hardware monitoring.

**Fix:** Blacklist both modules:

```bash
echo -e 'blacklist eeepc_wmi\nblacklist asus_wmi' | sudo tee /etc/modprobe.d/asus-wmi-blacklist.conf
```

No `mkinitcpio -P` needed — these modules aren't in initramfs. Reboot to apply.

**Note:** This is unrelated to the spd5118 suspend fix above. Blacklisting asus_wmi removes
a harmless warning; the spd5118 sleep hook fixes actual suspend failure. Both are needed.

**See also:** `asus_ec_sensors` is separately blacklisted in `/etc/modprobe.d/` due to
MangoHUD crash — see [mangohud-asus-ec-sensors workaround](../workarounds/mangohud-asus-ec-sensors.md).

**Date discovered:** 2026-03-15
