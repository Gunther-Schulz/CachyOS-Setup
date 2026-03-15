# ASUS XG27JCG Dual-Mode (5K/2K)

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
- **5K:** GNOME defaults to 4K → use `gdctl` to force 5K (see `xg27jcg-gnome-5k.sh`).
- Scale: 5K = 166%, 2K = 100%.

## Usage

**Toggle:** `ddc-mode-switcher` (from `ddc-mode-switcher` AUR package)

**Steam:** `ddc-mode-switcher mangohud %command%` — or use the scripts in `~/setup/scripts/` if not using the AUR package.

---

- [Mouse stutter](../peripherals/mouse-stutter.md) — i2c_dev
- [ddcutil](https://www.ddcutil.com/)
