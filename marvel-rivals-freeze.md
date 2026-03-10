# Marvel Rivals — Multi-Second In-Game Freezes

**In active testing.**

**Symptom:** Random multi-second full freezes of the game (only the game, rest of system responsive, audio continues). No pattern to combat/load — happens throughout sessions. Reproducible every session.

---

## Suspect 1: Split lock detection — **Most likely NOT the cause**

Applied `split_lock_detect=off`; freeze still occurred. Correlated with freeze timestamps but not causal.

**Theory:** UE5/Wine doing unaligned atomic memory operations (split locks) on the `GameThread` and `FChunkCacheWork` threads. The kernel's split lock detection fires a `#DB` hardware exception on every occurrence. Bursts correlate 1:1 with freeze timestamps in kernel log.

**Fix (if retesting):**

```bash
sudo sed -i 's/crashkernel=256M"/crashkernel=256M split_lock_detect=off"/' /etc/default/limine && sudo limine-update
sudo reboot
```

**Revert:**

```bash
sudo sed -i 's/ split_lock_detect=off//' /etc/default/limine && sudo limine-update
sudo reboot
```

---

## Suspect 2: VKD3D shader cache — **TESTING candidate**

**Evidence:** MangoHud captured 5.1 s single-frame freeze at 03:06:32. VKD3D log shows "Flushing disk cache" from pipeline library. Matches [vkd3d-proton #2793](https://github.com/HansKristian-Work/vkd3d-proton/issues/2793): NVIDIA RTX 50xx + driver 590.xx + VKD3D pipeline cache → multi-second freezes.

**Fix:** Add to Steam launch options:

```
VKD3D_SHADER_CACHE_PATH=0
```

**Tradeoff:** Shader compilation stutter on first encounter; no more multi-second freezes.

---

## Diagnosis commands (for future reference)

**Split lock events:**

```bash
journalctl -b -k --no-pager | grep "split lock" | grep -v "warning on user-space" | wc -l
```

**MangoHud log location:** `~/Marvel-Win64-Shipping_YYYY-MM-DD_HH-MM-SS.csv` (autostart_log=1 in MangoHud config)

**VKD3D log:** `2>/home/g/vkd3d.log` in launch options; check for "Flushing disk cache" around freeze time
