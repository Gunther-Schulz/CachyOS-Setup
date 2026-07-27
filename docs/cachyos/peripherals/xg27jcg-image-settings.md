# ASUS XG27JCG — image settings (SDR) + HDR verdict

**Machine:** Both (shared monitor — settings live in the monitor, not the host).

Companion to [xg27jcg-dual-mode.md](xg27jcg-dual-mode.md) (5K↔2K switching). This doc
covers picture quality: which OSD values, and why HDR stays off for desktop use.

## Verdict: HDR off for the desktop

`color-mode: default` on DP-2 — persisted in `~/.config/monitors.xml` (no `<colormode>`
entry = SDR). Toggle in GNOME Settings → Displays, or:

```sh
gdctl set --color-mode default    # SDR
gdctl set --color-mode bt2100     # HDR
```

**Why off.** The panel is edge-lit with **10 dimming zones**. With Dynamic Dimming off,
measured HDR contrast is ~1,300:1 — *identical to SDR* ([Tom's Hardware](https://www.tomshardware.com/monitors/gaming-monitors/asus-rog-strix-xg27jcg-27-inch-5k-gaming-monitor-review/5)).
DisplayHDR 600 is a brightness rating (785 nits measured full-field), not a contrast one.
So on SDR content HDR costs contrast and gains nothing.

**Observed on this unit:** with HDR on, SDR content looks softer and less punchy — washed
out / flat, i.e. lower apparent contrast across the image. Black levels still resolve;
shadow detail is not crushed. Nothing looks broken, which is why it's easy to second-guess.

**Why.** In SDR, desktop white maps to the panel max (354 nits) and black sits at whatever
the IPS backlight leaks — the full ~1,230:1. In HDR the compositor reserves headroom above
white for highlights, so desktop white maps to a *reference level* partway up instead, while
black is unchanged (the backlight leaks the same either way). Top of the range moves down,
bottom stays put → less range → "softer". GNOME's SDR level is
`org.gnome.mutter output-luminance` (default 100%), exposed as the SDR-brightness slider in
Settings → Displays when HDR is on.

**Why it reads as a colour problem when it isn't one.** Perceived colourfulness rises with
luminance (Hunt effect) and with contrast (Stevens effect). Compressing the luminance range
leaves colour coordinates untouched — measurably the same reds — but the eye reads them as
less vivid. So "colours less punchy" is an accurate description of a contrast change, not a
colour error, and there's nothing to correct in the Color menu.

Diagnosing which part bothers you: a large black area going dark-grey = lifted black floor
(not tunable here); a white page looking dim = reference-white mapping (tunable — the SDR
slider above); flat-looking photos with no identifiable wrong colour = Hunt/Stevens,
secondary to the contrast loss.

**The concrete cost:** while HDR is active the OSD greys out GameVisual, Contrast, Shadow
Boost, Blue Light Filter and the whole Color menu (manual p. 1-4) — every calibrated
setting below is out of circuit. Only Dynamic Dimming stays adjustable. DDC still *reports*
the old values; reported ≠ in effect.

Note [PC Gamer](https://www.pcgamer.com/hardware/gaming-monitors/asus-rog-strix-xg27jcg-review/)
reaches the opposite conclusion — "SDR content calibration in HDR mode is also really nicely
judged, so there's no real downside to enabling HDR" — but tested on Windows, where SDR-in-HDR
takes a different path than mutter's. The softness above is what this setup actually shows.

Worth enabling only for genuinely HDR games, where the 785-nit highlights pay off. Gaming
HDR is the mode to use there — measured "almost perfectly on spec"; Adjustable HDR only
unlocks sliders that break that.

## SDR settings

Verified against the monitor over DDC unless marked otherwise.

| Menu | Setting | Value | Note |
|---|---|---|---|
| Gaming | GameVisual | **Racing** | 2.35 dE out-of-box; calibration only reaches 0.34 dE — invisible gain |
| Gaming | Shadow Boost | Off | gaming aid; moves dark-tone gamma off reference |
| Image | Brightness | **30** | ambient-dependent, see below |
| Image | Contrast | **80** | where the ~1,300:1 measurements were taken |
| Image | Dynamic Dimming | Off | 10 edge-lit zones pump visibly on static content |
| Image | ASCR | Off | dynamic contrast — fights a calibrated setup |
| Image | Blue Light Filter | Off | panel is already TÜV low-blue-light at defaults; L4 locks brightness |
| Image | VividPixel | Off | edge enhancement → haloing |
| Image | Aspect Control | 16:9 | anything else blocks ELMB |
| Image | HDR Setting | Gaming HDR | dormant in SDR; the right mode when HDR is used |
| Color | **Display Color Space** | **sRGB** | ⬅ biggest win — see below |
| Color | Color Temp. | **6500K** | D65 |
| Color | Saturation | **50** | neutral midpoint |
| Color | Six-axis Saturation | default | per-hue correction without a meter is guessing |
| Color | Gamma | **2.2** | DDC `0x72` = `0x78`, middle of 1.8/2.0/2.2/2.4/2.6 |
| — | Sharpness | **50** | neutral midpoint |

**Display Color Space = sRGB is the one that matters.** The panel covers 94% DCI-P3 and
GNOME does no colour management for SDR apps, so on a wide-gamut setting everything is
oversaturated. Clamping in hardware fixes it — and it's *why* SDR mode beats HDR here.
Get the clamp from this setting, **not** from GameVisual sRGB Mode: that mode locks
Contrast, Shadow Boost, Colour and Dynamic Dimming, and Racing is the more accurate base.

**Brightness** is a room variable, not a calibration target. SDR max is 354 nits, so 30 ≈
105 nits — a dark-room value. Target: a white page looks like paper, not a lamp.

## Restore after All Reset

DDC-settable subset (OSD-only otherwise):

```sh
ddcutil --bus 5 setvcp 12 80      # contrast
ddcutil --bus 5 setvcp 14 0x05    # 6500K
ddcutil --bus 5 setvcp 87 50      # sharpness
ddcutil --bus 5 setvcp 8a 50      # saturation
ddcutil --bus 5 setvcp 72 0x78    # gamma 2.2  (0x64 = 2.0)
```

**Not DDC-settable** — set by hand in the OSD: Display Color Space, GameVisual, Dynamic
Dimming, ASCR, VividPixel, Blue Light Filter, Shadow Boost.

Save the finished state to **MyFavorite → Customized Setting 1** so a stray All Reset
doesn't cost the lot.

## Greyed-out OSD items

Two documented causes before suspecting a fault:

1. **Power Saving Mode** disables HDR, GameVisual, ELMB and colour adjustment outright —
   ASUS's own top answer ([FAQ 1056010](https://www.asus.com/support/faq/1056010/)). Fix:
   System Setup → Power Setting → **Standard Mode**.
2. **HDR Setting needs an HDR signal present** to be selectable — enable HDR host-side
   first, then pick the mode. Not the other way round.

## Open

- **Gamma cross-check.** PCWorld measured menu-2.2 producing an actual 2.4 in the *default
  wide-gamut* mode (needing menu-2.0 to hit 2.2); Tom's found Racing tracks reference. On
  Racing, 2.2 should be right — settle it with the
  [Lagom gamma test](https://www.lagom.nl/lcd-test/gamma_calibration.php) and drop to 2.0
  only if it reads high.
- **Contrast 80** is assumed-good, not confirmed as the shipped default (the manual lists
  no defaults; reading it would need a destructive reset). Verify no highlight clipping via
  the [Lagom contrast test](https://www.lagom.nl/lcd-test/contrast.php) — top two and bottom
  two blocks should stay distinct.
- Applied state below the DDC-readable subset (GameVisual, Display Color Space, ASCR,
  VividPixel, Blue Light Filter) is **unverified** — DDC exposes no codes for them.

---

- [xg27jcg-dual-mode.md](xg27jcg-dual-mode.md) — 5K↔2K switching, `ddc-mode-switcher`
- [../laptop/gnome-vrr-external-monitor-hybrid.md](../laptop/gnome-vrr-external-monitor-hybrid.md) — no VRR on this monitor on the laptop (NVIDIA `vrr_capable=0`)
- [manual](https://dlcdnets.asus.com/pub/ASUS/LCD%20Monitors/XG27JCG/XG27JCG_English.pdf) (OSD reference: §3.1.2)
