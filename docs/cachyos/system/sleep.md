# Desktop Sleep (S3) Fixes: spd5118 + asus_wmi/eeepc_wmi

**Machine:** Desktop (AM5/B850-G; S3 deep sleep). Do NOT apply on the laptop — it blacklists `asus_wmi`, which the laptop needs for `asusctl` (GPU MUX + keyboard).

## spd5118 (DDR5 temp sensor) blocks suspend

**Symptom:** suspend fails and the system hangs. Journal shows:
```
spd5118 8-0051: PM: dpm_run_callback(): spd5118_suspend [spd5118] returns -6
spd5118 8-0051: PM: failed to suspend async: error -6
PM: Some devices failed to suspend, or early wake event detected
```

**Cause:** the `spd5118` driver (DDR5 SPD-hub temp sensor) can't suspend — its SMBus device becomes inaccessible during the transition. The aborted S3 attempt can wedge the s2idle fallback too, especially once the NVIDIA GSP firmware heartbeat has already timed out.

**Fix:** unload the module before sleep, reload after wake, via a systemd sleep hook:
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
Preserves DDR5 temp monitoring while awake. **Alternative (loses monitoring entirely):** `echo "blacklist spd5118" | sudo tee /etc/modprobe.d/spd5118-blacklist.conf`.

## asus_wmi / eeepc_wmi — non-functional on this board, blacklisted

**Symptom:**
```
asus_wmi: failed to register LPS0 sleep handler in asus-wmi
asus_wmi: BIOS WMI version: 0.0
asus_wmi: SFUN value: 0x0
eeepc-wmi eeepc-wmi: Detected AsusMbSwInterface, not ASUSWMI, use DSTS
```

**Cause:** ASUS reuses one WMI GUID across laptops, desktops and netbooks, so `eeepc_wmi` auto-loads on the B850-G even though its features (backlight, wireless toggle, hotkeys) are laptop-only — `BIOS WMI version 0.0` / `SFUN 0x0` mean zero supported features, and LPS0 registration fails because S0ix/Modern Standby doesn't exist on AM5 desktops (S3 `deep` is correct here). `nct6775` + `k10temp` already cover hardware monitoring.

**Fix:**
```bash
echo -e 'blacklist eeepc_wmi\nblacklist asus_wmi' | sudo tee /etc/modprobe.d/asus-wmi-blacklist.conf
```
Not in initramfs — no `mkinitcpio -P` needed. Reboot to apply.

**Note:** unrelated to the spd5118 fix above — this silences a harmless warning; spd5118 fixes an actual suspend failure. Both are needed. `asus_ec_sensors` is separately blacklisted for a MangoHUD crash — see [mangohud-asus-ec-sensors.md](../workarounds/mangohud-asus-ec-sensors.md).
