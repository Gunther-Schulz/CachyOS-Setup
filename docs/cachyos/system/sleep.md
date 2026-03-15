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

**Related:** `asus_wmi: failed to register LPS0 sleep handler` — the ASUS board doesn't
support the modern s0ix/s2idle sleep path properly. S3 (`deep`) is the correct sleep mode
for this system. Current default is confirmed as `deep` via `cat /sys/power/mem_sleep`.

**Date discovered:** 2026-03-15
