# NVIDIA Dynamic Boost (nvidia-powerd) — dGPU stuck at base TGP

**Machine:** Laptop (FA607PV).

> **Not for the Desktop (9950X3D / RTX 5090).** Dynamic Boost is a **mobile-only** feature — it dynamically shifts a *shared* CPU+GPU power budget toward whichever needs it more. A desktop GPU has its own dedicated power delivery and a fixed (high) board power limit, so `nvidia-powerd` finds no Dynamic Boost platform and does nothing. Don't enable it on the desktop — it's a no-op there.

**Symptom:** In games the RTX 4060 Laptop GPU never draws more than its **base TGP (~55 W)** even at full load. `nvidia-smi` shows `Current Power Limit : 55 W` while `Max Power Limit : 140 W`, and performance is capped far below the card's potential (low GPU clock, often not hitting 100% util if the CPU is also throttled).

**Cause:** `nvidia-powerd` — the daemon that implements NVIDIA Dynamic Boost — ships installed but **disabled** (`preset: disabled`). Without it the driver never raises the GPU power limit above base TGP.

**Fix:**
```sh
sudo systemctl enable --now nvidia-powerd
```

**Verify** (under game load the limit should climb above 55 W toward 140 W):
```sh
systemctl is-active nvidia-powerd                                  # → active
nvidia-smi -q -d POWER | grep -E 'Current Power Limit|Max Power Limit'
nvidia-smi --query-gpu=power.draw,power.limit,clocks.gr,utilization.gpu --format=csv -l 1
```
Measured on the FA607PV (Marvel Rivals, AC, performance profile): limit **55 W → ~110 W**, draw **25 W → ~75 W**, GPU clock **1600 → 2625 MHz**.

**If the limit stays pinned at 55 W:** check `journalctl -u nvidia-powerd` for `no matching platform` — that means the SBIOS doesn't expose the Dynamic Boost interface (some laptops don't). On the FA607PV it works: the log shows `DBus Connection is established`, not an error.

**Pair with the CPU governor.** Dynamic Boost only helps when the platform is in a performance power profile and on AC. If the GNOME power mode is *Power Saver* → ACPI profile `low-power` → CPU governor `powersave`, the CPU gets clamped (~544 MHz observed) and starves the GPU regardless of Dynamic Boost. Use `gamemoderun` in Steam launch options (forces `performance` governor for the duration of the game), or set it manually:
```sh
powerprofilesctl set performance        # or: gamemoderun %command% in Steam
```
