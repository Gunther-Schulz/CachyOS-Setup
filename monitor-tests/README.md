# monitor-tests

Self-contained HTML test patterns for judging monitor settings by eye. No deps —
open in a browser, press <kbd>F11</kbd> for fullscreen, on the monitor being tested.

Written for the [ASUS XG27JCG](../docs/cachyos/peripherals/xg27jcg-image-settings.md)
but nothing here is model-specific.

| File | Judges |
|---|---|
| `overdrive-test.html` | Variable OD / overdrive — smear vs. overshoot |
| `black-level-test.html` | Black level, blooming, shadow detail (HDR on vs. off) |

## overdrive-test.html

Four grey-on-grey lanes plus a high-contrast reference. Grey-to-grey is the point:
overdrive is a grey-level mechanism ("improves the gray level response time" per the
OSD), so black↔white patterns — including TestUFO's default UFO — barely stress it.

**Track the moving block with your eyes.** Staring at a fixed point shows sample-and-hold
blur, which is an artifact of eye motion, present on every LCD, and unaffected by
overdrive. This is the usual reason the test reads as unjudgeable.

Read the **trailing** edge:

- dark smear behind → overdrive too low, raise
- bright halo / pale outline behind → overshoot, lower
- clean edge → correct

Judging one value in isolation is near-impossible. Calibrate on the extremes first: set OD
to 0 and memorise the smear, then 20 and memorise the halo, then compare the candidate
against both. If 0 and 20 look alike, the setting doesn't matter much on that panel — stop.

Controls: speed slider, <kbd>space</kbd> to pause.

## black-level-test.html

Five patterns, keys <kbd>1</kbd>–<kbd>5</kbd>: moving white box (follows the mouse),
white text on black, black-level steps (0,1,2,3,4,6,8,12 / 255), a small bright spot on
full black, and a letterbox simulation.

Built to compare HDR on vs. off. Toggle between runs:

```sh
gdctl set --color-mode default    # SDR
gdctl set --color-mode bt2100     # HDR
```
