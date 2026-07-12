# ASUS XG27JCG Dual-Mode (5K/2K)

**Machine:** Both (shared monitor — used on the laptop while the desktop is down).

5K (5120×2880 @180Hz) ↔ 2K (2560×1440 @330Hz) "Frame Rate Boost". Bus 5.

## VCP 0x03 soft controls

| Value | Effect |
|-------|--------|
| 1 | Open menu (Frame Rate Boost) |
| 20 | Confirm / select |
| 21 | Up |
| 22 | Down |
| 24 | Right |
| 16 | **DANGEROUS** — Display off. Avoid. To wake: press OSD buttons (likely the last/power button). In doubt, press all. |

**Toggle:** `ddcutil setvcp 0x03 1 --bus 5` then `ddcutil setvcp 0x03 20 --bus 5`

## GNOME

- **2K:** GNOME picks res/scale automatically.
- **5K:** GNOME defaults to 4K → force 5K with `gdctl`.
- Scale: 5K = 166%, 2K = 100%.

## Usage

**Primary use — Steam per-game launch wrapper.** For games you want at 1440p high-refresh (the 2K/330Hz mode), add `ddc-mode-switcher` to the game's **Launch Options** — it switches to 2K/330Hz for the game and restores 5K on exit:

```
ddc-mode-switcher mangohud %command%
```

Own tool — [`ddc-mode-switcher`](https://github.com/Gunther-Schulz/ddc-mode-switcher) (AUR package + command). Config: `~/.config/ddc-mode-switcher/config` (copy the repo's `config.example`). Match the monitor **by name** (v2.3.0+) so one config is portable across both machines regardless of which port it's plugged into — connector and i2c bus auto-detect:

```
MONITOR=XG27JCG
NATIVE_RES=5120x2880
TOGGLE_STEPS=("0x03 1" "0x03 20")
```

Also runs standalone to toggle 5K↔2K.

---

- [Mouse stutter](../peripherals/mouse-stutter.md) — i2c_dev
- [ddcutil](https://www.ddcutil.com/)
