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

**Toggle:** [`display-mode-switcher`](https://github.com/Gunther-Schulz/display-mode-switcher) — own tool, install from AUR.

**Steam:** `display-mode-switcher mangohud %command%`

---

- [Mouse stutter](../peripherals/mouse-stutter.md) — i2c_dev
- [ddcutil](https://www.ddcutil.com/)
