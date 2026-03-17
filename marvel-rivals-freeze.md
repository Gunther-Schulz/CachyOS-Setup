# Marvel Rivals — Multi-Second In-Game Freezes

**Root cause: NVIDIA driver bug on RTX 50xx (Wayland). Waiting for NVIDIA fix.**

**Symptom:** Random multi-second full freezes of the game (only the game, rest of system responsive, audio continues). No pattern to combat/load — happens throughout sessions. Reproducible every session. Issue has existed for over half a year.

**Tracking:** [NVIDIA/open-gpu-kernel-modules#880](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/880) — "RTX 5090 often freezes presentation for 3-5 seconds in certain games" (OPEN, 81+ comments, NVIDIA has **not** been able to reproduce it internally despite trying since July 2025; internal bug 5376205)

---

## Primary cause: NVIDIA RTX 50xx driver bug (Wayland)

Affects multiple games (Marvel Rivals, Overwatch, Cyberpunk, The Finals, RE:Requiem) on RTX 50xx under Wayland with drivers 590.xx–595.xx. NVIDIA has reproduced the issue but has not released a fix as of driver 595.45.04.

**Characteristics:**
- Exactly ~5 second freezes (3–5 s range)
- GPU load drops to 0%, GPU clock drops to idle (600 MHz) during freeze
- Audio continues, rest of system responsive
- No NVIDIA Xid errors, no kernel errors, no OOM — completely silent in logs
- Happens on Wayland; some users report X11 is unaffected (switching to X11 is not an option; running Proton in XWayland mode did not help)

**Current status:** No fix available. No known mitigations. Alt-tabbing or pressing super key may unfreeze the game faster than waiting.

---

## Ruled out: Split lock / bus lock detection

**Status: Ruled out (2026-03-17)**

Split lock mitigation was disabled at runtime (`kernel.split_lock_mitigate=0`) and the freeze still occurred (5289 ms at 11:15:37). Bus lock traps are a symptom being logged, not the cause of the stalls.

Split lock mitigation remains disabled via sysctl to reduce unnecessary thread penalties (4,809+ traps per session from UE5/Wine/anti-cheat threads), but this is just a symptom — does not fix the freezes.

**Config:** `/etc/sysctl.d/99-split-lock.conf`

```
kernel.split_lock_mitigate=0
```

**Revert:**

```bash
sudo sysctl kernel.split_lock_mitigate=1
sudo rm /etc/sysctl.d/99-split-lock.conf
```

---

## Ruled out: VKD3D shader cache flush

**Status: Ruled out — just a symptom**

VKD3D pipeline cache flush correlated with some freezes ("Flushing disk cache" in VKD3D logs, matches [vkd3d-proton#2793](https://github.com/HansKristian-Work/vkd3d-proton/issues/2793)). Disabling the cache (`VKD3D_SHADER_CACHE_PATH=0`) did not fix the freezes — they continued with identical characteristics. The cache flush was likely a consequence of the driver stall, not a cause.

`VKD3D_SHADER_CACHE_PATH=0` remains in launch options but is not a mitigation.

---

## Diagnosis commands (for future reference)

**Split lock / bus lock events:**

```bash
journalctl -b -k --no-pager | grep "bus_lock\|split lock" | grep -v "warning on user-space" | wc -l
```

**Bus lock events around a specific time:**

```bash
journalctl -b -k --since "HH:MM:00" --until "HH:MM:00" --no-pager | grep "bus_lock"
```

**MangoHud log location:** `~/Marvel-Win64-Shipping_YYYY-MM-DD_HH-MM-SS.csv` (autostart_log=1 in MangoHud config)

**Find freezes in MangoHud CSV (frametime > 500ms):**

```bash
awk -F',' 'NR>3 && $2 > 500 {print NR": fps="$1" frametime="$2"ms"}' ~/Marvel-Win64-Shipping_*.csv
```

**VKD3D log:** `2>/home/g/vkd3d.log` in launch options; check for "Flushing disk cache" around freeze time
