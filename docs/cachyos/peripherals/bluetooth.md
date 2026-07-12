# Bluetooth

```bash
systemctl enable --now bluetooth
```

**Logitech Bolt mouse lag:** See `mouse-lag-troubleshooting.md` in reference (content) for lag → choppy → snappy troubleshooting.

**Galaxy Buds 2 Pro:** Appear twice in BT list. Try the second entry first; first may connect but not be selectable as output.

## SMSL AO300PRO amp — "searching" after reboot

**Machine:** Laptop. MAC `7C:FE:62:FB:80:AA`.

**Symptom:** After a reboot the amp display stays on "searching"; `bluetoothctl info` shows `Connected: yes` but `pactl list sinks short | grep bluez` shows **no sink**.

**Cause:** Boot race — `bluetoothd` auto-connects the trusted amp before WirePlumber's BT backend is up, so no A2DP audio node is created. The link is "up" with nowhere to send audio.

**Manual recovery:**
```bash
bluetoothctl disconnect 7C:FE:62:FB:80:AA; sleep 2; bluetoothctl connect 7C:FE:62:FB:80:AA
# sink appears as bluez_output.7C_FE_62_FB_80_AA.1; set it default:
pactl set-default-sink bluez_output.7C_FE_62_FB_80_AA.1
```
If it still won't lock on, the link key is stale → `bluetoothctl remove 7C:FE:62:FB:80:AA`, put amp in pairing mode (fast blink), then `scan on` / `pair` / `trust` / `connect`.

**Permanent fix (installed):** a user service bounces the connection ~6 s after WirePlumber is ready, so the sink always builds. The unit is **tracked in dotfiles** (`laptop/bt-amp-reconnect.service`, deployed by `install.sh` on the laptop) — enable it:
```bash
systemctl --user enable bt-amp-reconnect.service
```
Suspend/resume can drop BT audio the same way — if it does, hook the same script to resume (system service `WantedBy=post.target` under `[Install]`, ordered `After=suspend.target`).
