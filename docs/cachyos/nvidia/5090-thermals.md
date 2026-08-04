# RTX 5090 — thermal baseline and what the numbers mean

**Machine:** Desktop.

Measured with [`tools/gpu-thermal.sh`](../../../tools/gpu-thermal.sh). Temperatures
come from `nvidia-gpu-sensors`, not `nvidia-smi` — NVIDIA removed memory-junction and
hotspot from the public query surface on the 50-series; see the GPU items in
[todo.md](../todo.md).

## Baseline

| | Idle | `gpu_burn` 10 min |
|---|---|---|
| Core | 46.0 °C | **87.2 °C** |
| Memory junction | 58.0 °C | **100.0 °C** |
| Hotspot | 50.0 °C | **99.0 °C** |
| Power | ~25 W | **575 W** (peak 579.9) |
| GPU fan | 0 % | 84 % |
| Case fan | ~750 rpm | 1 523 rpm |
| AIO fan | ~1 240 rpm | 2 509 rpm |

326 samples at 2 s. Power limit 575 W, max settable 600 W.

## Verdict: healthy. Power-limited, not thermally limited.

**The card has never thermally throttled — lifetime counter zero.**

```
SW Power Cap                 : Active        ← the actual limiter
HW Thermal Slowdown          : Not Active
SW Thermal Slowdown          : Not Active
SW Thermal Slowdown counter  : 0 us
```

This covers memory too, which is the part that makes it load-bearing: NVIDIA's NVML
documentation states `SW Thermal Slowdown` fires when **either** GPU temperature
**or** memory temperature exceeds its max operating point
([nvmlClocksThrottleReasons](https://docs.nvidia.com/deploy/nvml-api/group__nvmlClocksThrottleReasons.html)).
An OR'd flag that never fired is evidence about the 100 °C memory reading, not only
about the core.

**Hotspot − core delta: 8.8 °C steady state, 14.4 °C peak.** Community-accepted
bands (forum consensus, not vendor-published) are 10–15 °C normal, ≤20 °C acceptable,
>20 °C indicating uneven mounting or a thermal-interface problem. This card sits at
or below the *normal* band — the die mount is good. Worth stating because it is
checkable here at all: the delta is normally unreadable on Blackwell without NVIDIA's
internal MODS tool, which is how an RTX 5070 Ti ran at
[107 °C hotspot on bad factory TIM](https://www.tomshardware.com/pc-components/gpus/hotspot-temperature-sensor-on-nvidias-blackwell-gaming-gpus-is-still-accessible-if-you-have-access-to-nvidias-internal-mods-tool-nvidia-rtx-5070-ti-caught-throttling-at-107-c-over-poor-tim-application)
undetected.

**`gpu_burn` is a power virus, not a workload.** It pins 575 W continuously in a way
no game does — TechPowerUp deliberately excludes this class of tool from review
methodology for that reason. Reviewer *gaming* figures for the FE are core 72–80 °C
and memory 89–96 °C; these numbers being higher is expected, not worse cooling.
Treat this as the worst case the machine can produce.

⚠️ **No primary-source GDDR7 max junction temperature exists in anything reachable.**
Samsung/SK Hynix datasheets and the JEDEC JESD239.01 standard are paywalled or
unpublished. The widely repeated "~105 °C" figure could not be confirmed for GDDR7
specifically — **do not treat 100 °C as "5 °C from the limit"**, because that limit
is not established. The card's own firmware not throttling is the stronger evidence.

## The FE does run hot — but the baseline above overstates it

Two things are true at once and must not be conflated.

**The card design runs warm, and that is a documented reviewer finding, not a
feeling.** 575 W through a 2-slot cooler; GamersNexus measured the FE at core 72 °C
and **memory 89–90 °C on a gaming loop at 21–22 °C ambient**, and explicitly flagged
it as *"ran warm… concern for hotbox cases"*
([review](https://gamersnexus.net/gpus/nvidia-geforce-rtx-5090-founders-edition-review-benchmarks-gaming-thermals-power)).
AIB triple-fan cards do better — a Gigabyte AORUS MASTER managed core 73.9 °C and
GDDR7 junction 74 °C under FurMark, which is a different league of cooler.

**But this machine's numbers are NOT comparable to those.** The baseline above is
`gpu_burn` — a power virus holding 575 W continuously. Reviewer figures are gaming
loops. Comparing worst case against typical makes any card look bad.

⚠️ **Gap: no gaming-load measurement exists for this card.** Until one does, "is my
GPU unusually hot?" is unanswerable — the only like-for-like comparison is a
representative gaming/render load at a known ambient. Ambient here is also
unmeasured, and it enters directly: GamersNexus ran at 21–22 °C, and a warm room
adds to every number one-for-one.

```sh
# a fair comparison against reviewer figures
sudo ./tools/gpu-thermal.sh gaming -l "<game or superposition benchmark>" -t 900
```

## Reducing the heat: what is worth doing, ranked

The 8.8 °C hotspot delta means the cooler-to-die interface is fine, so **there is no
defect to repair**. What remains is lowering heat *input* or improving heat *removal
from the case*.

1. **Power limit — biggest lever, instant, reversible, no BIOS.** Adjustable
   **400–600 W** (currently 575). This is the GPU's ECO Mode, and the CPU result
   suggests the shape: community reports cluster around ~90 % performance at
   ~70–75 % power. One command, revertible on the spot, and it survives nothing —
   re-apply after reboot if kept.
   ```sh
   sudo nvidia-smi -pl 450
   sudo ./tools/gpu-thermal.sh pl450          # then diff against gpu-stock
   sudo nvidia-smi -pl 575                    # revert
   ```
   Do this **before** clock-offset undervolting: it is one variable, it cannot
   destabilise anything, and it establishes how much of the heat is simply power.
2. **GPU-driven case fan curve** — see below; targets a measured lag, costs nothing.
3. **Clock-offset undervolting** (`nvidia-settings` offset + reduced power limit) —
   the fuller technique, more performance retained per watt, but it can destabilise
   and needs its own validation. See the GPU item in [todo.md](../todo.md).

❌ **Do not repaste or replace pads.** The FE ships with liquid-metal TIM, opening it
is high-risk, and the measured 8.8 °C delta says there is nothing to gain — that is
what a good mount looks like. The 5070 Ti repaste story is about a card whose hotspot
hit 107 °C; this one does not.

## GPU undervolt vs CPU Curve Optimizer — different failure modes

**GPU undervolting does not carry the idle-crash risk that CPU CO does.** The
mechanisms differ in where they bite:

| | CPU Curve Optimizer | GPU undervolt |
|---|---|---|
| Fails at | **idle / light load** — one core boosting to max frequency at reduced voltage | **under load** — high clocks are where the margin disappears |
| Symptom | spontaneous reboot, freeze, WHEA | driver reset, `Xid` in the journal, artifacts, application crash |
| Recovery | reboot, possibly CMOS clear | usually the app dies; revert with one command |
| Revert | BIOS visit | `nvidia-settings` / `nvidia-smi`, live, no reboot |

At idle the GPU sits at low clocks and low voltage with enormous margin, so an
aggressive offset simply never gets exercised there. That makes it **deterministically
testable**: run the load, watch for artifacts and
`journalctl -b | grep -i xid`. No waiting around for a random failure during work.

⚠️ **Caveat:** severe instability can still hard-hang the machine (e.g. Xid 79,
"GPU has fallen off the bus"). Rare at modest offsets, and it happens under load —
i.e. while testing, not while working.

### ❌ RETRACTED: "there is no V/F curve editor on Linux"

**Wrong, twice over** (researched and code-inspected 2026-08-04):

**1. A real per-point V/F curve editor exists for Linux.**
[`ekojsalim/nvcurve`](https://github.com/ekojsalim/nvcurve) does Afterburner-style
per-point curve editing, **explicitly tested on RTX 5090 / Blackwell**, by calling
undocumented NvAPI functions through `libnvidia-api.so`. A LACT proof-of-concept for
the same API path exists too ([issue #936](https://github.com/ilya-zlobintsev/LACT/issues/936),
tested on a 5090).

**2. The premise about Afterburner was also wrong.** Since **GPU Boost 3.0** (Pascal,
2016) Afterburner does **not** set absolute voltage either. It sets a *frequency offset
at each of up to 128 fixed voltage points* NVIDIA burns into the GPU
([SkatterBencher](https://skatterbencher.com/nvidia-gpu-boost-3-0/)). So NVCurve is not
an approximation of Afterburner — it is the same mechanism. "Set an absolute millivolt
value" is unavailable on **both** operating systems for Pascal-and-later NVIDIA GPUs.

**Safety, verified by reading its NvAPI surface rather than its README.** Every call it
makes is either a clock write or a voltage *read*:

| Call | Direction |
|---|---|
| `nvmlDeviceSetGpcClkVfOffset`, `nvmlDeviceSetMemClkVfOffset` | write — clock offsets, **public documented NVML** |
| `SetClockBoostTable` (`0x0733E009` = `ClkVfPointsSetControl`) | write — per-point curve, undocumented NvAPI |
| `GetCurrentVoltage`, `GetVoltBoostPercent` | **read only** |

**There is no voltage-set path in the tool.** It cannot raise voltage above the points
NVIDIA burned into the VBIOS, so the failure mode is instability, not overvoltage
damage. It also carries a dedicated `safety.py` whose docstring states *"Every write
path calls validate_write() before touching hardware."*

⚠️ **Caveats, stated rather than buried.** The NvAPI functions are undocumented and the
project's own warning says they "may change or disappear between driver releases" —
re-verify after every driver update. Compatibility with **610.43.03 specifically is
untested**; the confirmed testing was on adjacent versions. And unlike
`nvidia-gpu-sensors` (772 lines of C, read fully before running), this is ~5 100 lines
of Python plus a React UI — **the NvAPI surface was inspected, not the whole codebase.**

### The power limit is a SEPARATE lever, not half of the undervolt

NVIDIA does not expose a V/F curve editor on Linux — that is Afterburner on Windows.
What exists here (confirmed on driver 610.43.03):

- `GPUGraphicsClockOffsetAllPerformanceLevels`, range **−1000 … +1000** MHz
- `nvidia-smi -pl`, range **400–600 W**

**Corrected 2026-08-04 — an earlier version of this section said the power limit was
half the undervolt. It is not.** The real pairing is **offset + clock lock**:

- A **positive clock offset** shifts the whole V/F curve along the frequency axis: each
  existing voltage point now yields more clock. On its own it does *not* raise voltage —
  it only becomes an overclock if the card is left free to boost to a higher point.
- **`nvidia-smi -lgc`** stops it doing exactly that. With the clock capped, the card
  sources that clock from a *lower* point on the original curve → **less voltage at the
  same clock**. **The lock, not the power limit, is what makes it an undervolt.**
- **The power limit is orthogonal.** It never touches the curve; it makes the boost
  algorithm back off to a lower point whenever the power budget would be exceeded. A
  useful extra lever, stacked on top by preference — **not a requirement.**

So declining the power limit costs nothing here. `offset + -lgc` is a complete
undervolt without it (operator preference, 2026-08-04).

⚠️ **"The pairing is the only route" is under test, not established.** It is the
commonly documented Linux recipe, which is not the same as a technical necessity —
and this repo already has a precedent against assuming the public API is the limit:
hotspot and memory-junction temperature are absent from every public NVIDIA interface
on this generation, yet `nvidia-gpu-sensors` reads them through the driver's own
ioctls. `NV2080_CTRL_CMD_VOLT_VOLT_RAILS_GET_STATUS` already **reads** NVVDD/MSVDD on
this card; whether a SET path exists is an open question, not a closed one.

### Acceptance criteria for any undervolt method (operator, 2026-08-04)

A method that produces good benchmark numbers but fails these is not a solution:

1. **The card must still idle down.** A fixed clock is disqualifying. Note
   `nvidia-smi -lgc` takes a `<min,max>` **pair** — verified in this driver's own help
   text — so a ceiling cap with a low floor (`-lgc 210,2600`) preserves idle
   behaviour, while a singular value (`-lgc 2600`) pins the clock and does not. An
   earlier note here described `-lgc` as "locking to a fixed clock"; that conflated the
   two forms.
2. **It must survive reboot** without manual re-application, or come with the unit that
   reapplies it. Clock offsets, power limits and `-lgc` are all **runtime state**, and
   `persistence_mode` is currently **Disabled** on this machine.
3. **No per-application or per-game fiddling.** Anything needing a command before each
   workload is not a daily-driver answer.

## The V/F curve, read from this card (2026-08-04)

✅ **`nvcurve setup` → "Compatible" on driver 610.43.03.** All eight NvAPI functions
resolved, all seven read tests passed, the write-verify wrote +5 MHz to point 126 with
**no collateral changes** and restored cleanly. That closes the one gap the research
could not: the undocumented NvAPI path was only confirmed on adjacent driver versions.

**132 active points** — 127 GPU core (180–3180 MHz, 450–1240 mV) and 5 memory
(405–14 001 MHz, 530–710 mV). Snapshots land in `/var/cache/nvcurve/snapshots/`.

### The top of the curve is very poor value

Taking point 80 (2 580 MHz @ 950 mV) as the reference, and modelling power as **V²·f**:

| Point | MHz | mV | Δ clock | Δ power | MHz per +10 mV |
|---|---|---|---|---|---|
| 79 | 2 565 | 945 | −0.6 % | −1.6 % | **90** |
| 80 | 2 580 | 950 | 0 % | 0 % | 30 |
| 86 | 2 700 | 990 | +4.7 % | +13.6 % | 25 |
| 92 | 2 820 | 1 025 | +9.3 % | +27.2 % | 27 |
| 100 | 2 917 | 1 075 | +13.1 % | +44.8 % | 18 |
| 116 | 3 090 | 1 175 | +19.8 % | +83.2 % | 16 |
| **126** | **3 180** | **1 240** | **+23.3 %** | **+110.0 %** | **14** |

**The card more than doubles its power for less than a quarter more clock.** The
efficiency knee sits around **points 78–80, 2 520–2 580 MHz at 940–950 mV**: below it
the curve returns ~90 MHz per 10 mV, above it that collapses to 14.

⚠️ **The Δ-power column is a first-order V²·f model, not a measurement.** It ranks the
points correctly and is the right basis for *choosing* a target; the actual saving must
be measured with `gpu-thermal.sh`, not taken from this table.

### ⚠️ First result: the PERFORMANCE gain is at or below the noise floor

Sweep of global V/F offsets +50 → +300 (2026-08-04), all passing `gpu_burn` with
`errors: 0`:

| Offset | gpu_burn GFLOP/s | FurMark FPS (operator, on-screen) |
|---|---|---|
| +50 | 63 844 | ~440s |
| +100 | 63 248 | ~440s |
| +150 | 63 446 | ~440s |
| +200 | 63 847 | ~440s |
| +250 | 63 861 | ~440s |
| +300 | 64 480 | ~440s |

**A 1.9 % spread across 250 MHz of offset, with no trend.** Operator's assessment —
*"if there is a change it's marginal and looks like noise"* — matches the data.

**Why, and it is structural rather than a measurement failure:** both test loads are
**power-capped at 575 W**. Under a hard cap an offset cannot buy clock — it can only buy
whatever extra clock the freed voltage allows *before power hits the ceiling again*. A
hand-sampled live reading gave **~2 174 MHz at +300 vs ~2 125 MHz at stock**, both at
575 W and 86–87 °C: **≈ +2 %**, which is real but too small for these instruments to
separate from run-to-run variance. `gpu_burn` additionally cannot see clock at all — on
268 MB matrices it is bandwidth-bound.

**The benefit worth chasing on this machine is thermal, not performance.** Same work at
lower voltage means less heat, and the operator's actual complaint is fan noise, not
frame rate. FurMark ran **80 °C at +250 against 87 °C at stock** — but the sweep has **no
cooldown between steps**, so the card accumulates heat and later offsets are tested under
*worse* conditions than earlier ones. That 7 °C is therefore **not trustworthy**, and it
points the opposite way to the bias, which makes it interesting rather than conclusive.

**⚠️ Known defects in this sweep's measurements** (pass/fail verdicts are unaffected —
`errors:`, crashes and `Xid` are robust): `sensors_line` samples *after* the load exits,
so every clock/power/temp figure in `progress.log` is an **idle reading**; FurMark runs
with `--no-score-box` so no FPS is captured; one sample per offset, so no variance
estimate; and no thermal control between steps.

### An undervolt is an overclock at fixed voltage — which is why FPS can RISE

The name misleads. The edit is not "less voltage at the same clock"; there is no
voltage knob. It is **more clock at the same voltage** — raise the frequency at a
chosen point, then flatten everything above it. The card then reaches your target clock
at a *lower* point on the curve than it used to, so the voltage it applies for that
clock falls out as a consequence.

Two distinct effects, and both are real:

- **Not power-limited** (light and medium loads, high frame rates): the card was going
  to run 2 800 MHz anyway, at ~1 020 mV. After the edit it runs 2 800 MHz at ~950 mV.
  Same FPS, **~13 % less power, cooler and quieter.**
- **Power-limited** (heavy load — this card sat at **2 085 MHz** under `gpu_burn`
  purely because the 575 W cap bound first): more clock per volt means more clock
  inside the same budget. The equilibrium moves up. **FPS actually increases**, and
  power is unchanged because the cap still binds — the win shows up as performance
  rather than as temperature.

⚠️ **Correction to an earlier version of this section**, which said a curve edit "would
barely change the power-virus numbers". That describes only the *flattening* half — a
cap alone changes nothing below itself. The half that matters is **raising** frequency
at the voltage points the card actually uses, and under a power limit that is precisely
where the gain comes from.

### Independent corroboration — another 5090 owner, same diagnosis, same fix

A forum report (MSI 5090 Ventus 3X OC + 9800X3D, Aug 2025) matches this investigation
on three points and settles one of its open questions.

**1. He saw the same curve deficit, and reached the same conclusion.** At 0.98–1.0 V his
stock card produced only 2 300–2 400 MHz, which he describes as *"WAY under the AB
voltage curve's expected frequencies for those voltages"* — the identical observation
made here (2 665 MHz at 1.075 V against a curve value of 2 917). He attributed it to the
575 W limit throttling the card. That is the clamping diagnosis, arrived at
independently on different hardware.

**2. It answers the "is +1000 MHz at 900 mV achievable?" question — yes.** His setting is
**0.9 V @ 2 900 MHz, flattened above**, described as *"rock solid stable"*, running
0.86–0.89 V at 2 500–2 800 MHz in practice. This repo flagged that magnitude as untested
and possibly implausible; it is neither. The low-voltage curve points are tuned for idle
efficiency, not silicon limits.

**3. It resolves the performance-OR-quiet framing — a flatten gives BOTH, workload-dependent.**

| His workload | Power state | What the flatten produced |
|---|---|---|
| 3DMark Steel Nomad | **at the 575 W cap** | **+7.2 % score at UNCHANGED power** (13 780 → 14 770) |
| VR flight sims | below the cap | *"noticeably reducing temps and power consumption"* |

**One setting, two behaviours.** Power-limited work converts the freed voltage into
clock; unconstrained work converts it into lower power. The card decides, per workload.
Earlier framing in this document treated these as a choice — they are not.

⚠️ **It also calibrates our model, downward.** His numbers: 2 470 MHz @ 0.965 V →
2 610 MHz @ 0.870 V, both at 575 W. A pure V²·f model predicts **3 039 MHz**; he got
**2 610** — the model **over-predicts by 16 %**, because memory and static/leakage power
are not in it. So the **−31 % power estimated for an 890 mV anchor here is optimistic**;
expect nearer −20 %.

⚠️ **And his stock regime is not ours.** His Steel Nomad ran at the cap; this card's
GravityMark run sits at **370 W of 575** with 189 W spare. So the "more performance"
face will show up here in genuinely heavy work (like `gpu_burn`, which does pin 575 W),
and the "less power" face in the lighter loads already measured.

### Same operation as CPU Curve Optimizer, expressed in the mirror

Calling the CPU work an "undervolt" and the GPU work an "overclock" is a naming
accident, not a real difference. Both shift the same V/F curve; the vendors simply
label opposite axes of it.

| | CPU — AMD Curve Optimizer | GPU — NVIDIA curve |
|---|---|---|
| Knob is expressed as | **voltage** offset at each frequency (−15 = less voltage) | **frequency** offset at each voltage (+200 MHz = more clock) |
| What it actually does | shift the V/F curve so the chip does more work per volt | **identical** |
| Why it can *raise* performance | lower voltage → thermal/power headroom → higher sustained boost | more clock per volt → more clock inside the power cap |
| Risk | the chip must beat its validated V/F point | **identical** |
| **Fails at** | **idle / light load** — one core boosting high at reduced voltage | **under load** — high clocks are where margin vanishes |
| Recovery | BIOS visit, possibly CMOS clear | one live command, no reboot |
| Granularity | one offset per core; Curve Shaper adds a frequency × temperature grid | per-point across 128 voltage points |

Both are asking silicon to exceed what the vendor validated, and both work for the same
reason — factory curves are conservative enough to cover the worst chip in the batch.
**The differences that matter operationally are the last two rows, not the naming.**
Curve Optimizer is the riskier one to live with, because its failures land while you are
working and cost a BIOS trip; a GPU curve edit fails while you are testing it and is
undone with a command.

**The catch, stated plainly: this is an overclock and carries an overclock's risk.**
Asking for 2 800 MHz at 950 mV means running the silicon past the point NVIDIA
validated for that voltage. It works because factory curves are conservative enough to
cover the worst chip they shipped — but how much headroom *this* chip has is a silicon
lottery, and pushing past it produces artifacts, driver resets or `Xid` errors. There is
no free lunch; there is an unclaimed margin, of unknown size until measured.

### The voltage/clock gap: real, systematic — and it is the power cap, not slack

Drilled into the 326 samples of the stock run. The gap is **not** a sampling artefact —
the joint distribution is tight and consistent:

| NVVDD | samples | mean SM clock | curve says that voltage gives |
|---|---|---|---|
| 0.995 V | 121 | **2 103 MHz** | 2 715 MHz |
| 1.000 V | 83 | **2 127 MHz** | 2 752 MHz |
| 1.020 V | 13 | **2 205 MHz** | 2 805 MHz |
| 1.075 V | 29 | **2 224 MHz** | 2 917 MHz |

Roughly **600 MHz below the curve at every voltage**, across hundreds of samples.

**But the cause is visible in the timeline, and it is the 575 W cap.** The card was
power-limited from the *fourth second*:

```
t+2    SM   180 MHz   0.800 V    20.6 W     ← idle
t+4    SM  2287 MHz   1.020 V   570.0 W     ← already at the cap
t+6    SM  2272 MHz   1.020 V   575.0 W
```

It was never free. Temperature is not the limiter either — 2 355 MHz at **65.6 °C** and
2 370 MHz at **86.4 °C** both sit at 575 W, i.e. 21 °C apart at the same clock and power.

**The one sample that escaped the cap proves the point:** `2 722 MHz @ 1.075 V,
515.8 W` — the single reading below the power limit, and the highest clock of the run.
Against a curve value of 2 917 MHz it is 195 MHz short (6.7 %), not 600. **The gap
scales with how hard the power limiter is working**, so it is clamping, not a fixed
offset.

❌ **Retracted: "~90–150 mV of slack at the operating point."** There is no free voltage
headroom sitting there; the run simply measured a clamped state end to end.

⚠️ **Two explanations remain, and this data cannot separate them:**
1. The limiter clamps *frequency* while voltage tracks the higher requested curve
   point — an inefficient state that an undervolt would directly fix.
2. The reported `NVVDD` is a rail setpoint including load-line/droop compensation
   rather than effective die voltage, in which case the "real" voltage is lower and the
   curve is being honoured after all — no anomaly.

### ✅ RESOLVED 2026-08-04 — explanation 1. The limiter was clamping.

Unigine Superposition, **4K Optimized**, OpenGL 4.4, 85 loaded samples:

| | `gpu_burn` (power virus) | **Superposition 4K** |
|---|---|---|
| power | **575 W — capped** | **493 W mean / 514 W max — NOT capped** |
| SM clock | ~2 125 MHz | **2 665 MHz mean / 2 707 max** |
| GPU utilisation | 100 % | 100 % |
| NVVDD | 0.995–1.075 V | **1.075 V, all 85 samples** |
| clock at 1.075 V | 2 224 MHz | **2 665 MHz** |
| **deficit vs curve** (2 917 MHz @ 1 075 mV) | **693 MHz / 23.8 %** | **252 MHz / 8.6 %** |

**The deficit shrinks by two-thirds the moment the power cap stops binding.** That is
explanation 1 confirmed: the limiter clamps *frequency* while voltage holds at the
requested curve point. Explanation 2 (load-line compensation inflating the reading)
would have produced a constant offset regardless of power state; it did not.

### The 252 MHz residual: about half is temperature, measured

All 85 loaded Superposition samples sat at **exactly 1.075 V** and below the power cap,
which makes them a controlled set — voltage fixed, only temperature varying:

| core temp | mean SM clock | mean power |
|---|---|---|
| 60 °C | **2 705 MHz** | 475 W |
| 68 °C | 2 677 MHz | 486 W |
| 74 °C | 2 669 MHz | 485 W |
| 80 °C | 2 643 MHz | 503 W |
| 82 °C | **2 648 MHz** | **505 W** |

**Pearson r = −0.737 over 85 samples, slope −2.5 MHz per °C.** A clean monotonic
relationship: NVIDIA's boost algorithm steps clocks down with temperature independently
of the power limit, so a hot card is slower at the same voltage.

### ✅ CLOSED — the GravityMark trace explains the whole gap. The curve IS honoured.

GravityMark is geometry-heavy but **power-light**: 338 W mean, 379 W max, **never once
near the cap** (0 of 81 loaded samples ≥ 570 W) — and it produced the **highest clocks
measured on this card**, 2 823 MHz mean at 1.075 V. Its peak sample is decisive:

| condition | power | core temp | clock at 1.075 V | vs curve (2 917 MHz) |
|---|---|---|---|---|
| **GravityMark peak** | **106 W** | **54.9 °C** | **2 895 MHz** | **−22 MHz (0.8 %)** |
| GravityMark mean | 338 W | 67 °C | 2 823 MHz | −94 MHz |
| Superposition | 493 W | ~78 °C | 2 665 MHz | −252 MHz |
| `gpu_burn` | 575 W (capped) | ~87 °C | 2 224 MHz | −693 MHz |

**Cold and lightly loaded, the card lands within 22 MHz of its curve value.** The deficit
is not a fixed offset, a droop artefact or a hidden guard — it is the monotonic product
of temperature and power draw, exactly as the −2.5 MHz/°C slope predicted. The V/F curve
frequency is a **cold, light-load maximum**, and every earlier "unexplained residual" was
this effect measured at a different operating point.

Nothing further to investigate here. It also confirms the practical claim underneath the
undervolt: **heat is what is costing clocks**, and it is worth ~670 MHz between the best
and worst operating points on this card.

### Leakage is visible in the same data — and it argues for the undervolt

Look at the power column above. From 60 °C to 82 °C the card draws **+30 W (475 → 505)
while delivering 57 MHz LESS**, at identical voltage and workload. That is silicon
leakage: a hotter chip converts fewer watts into work.

Combined effect ≈ **8.6 % efficiency lost across 22 °C.** Two consequences worth
carrying: any benchmark comparison must control for starting temperature, and **cooling
and undervolting compound** — less voltage means less heat means less leakage means more
clock per watt, in the same direction twice.

⚠️ **This does NOT establish "the card is not power-limited at gaming load."** Superposition
on Linux runs **OpenGL 4.4**, and its 4K Optimized score here was ~33 % below comparable
5090 systems on the leaderboard. **100 % utilisation does not mean maximum power draw** —
it means the scheduler always had work, not that the work was power-dense. A less
efficient render path can keep the GPU busy while extracting less throughput per watt,
so 493 W may reflect *this workload's* power density rather than the card's ceiling
under a modern Vulkan or DirectX-via-Proton title with heavy RT and tensor work.

**What survives regardless:** the clamping-vs-load-line question. That comparison only
needed two *different power states*, and it got them — the 693 → 252 MHz change across
the cap boundary is real whatever the workload's absolute weight.

**What does not survive:** any claim about how this card behaves in real games. One
benchmark on a weak API path is not that. **Open — the card never exceeded 1.075 V in
either run despite a curve reaching 1 240 mV, so it may be voltage-ceiling limited at
gaming load; but that is a hypothesis from two unrepresentative loads, not a finding.**

❌ **Rejected: "run 8K Optimized to see if a heavier load hits the cap."** The
leaderboard systems ran **the same 4K preset** and scored 50 % higher, so workload weight
is not the variable — the platform is. A heavier preset on the same handicapped path
measures a different point on that path, not the card's ceiling.

### ✅ The card is NOT the problem — Vulkan reaches the power cap

FurMark 2.10.2 **Vulkan** mode (Vulkan 1.4.341), sampled live 2026-08-04:

| | Superposition 4K (**OpenGL**) | FurMark (**Vulkan**) |
|---|---|---|
| power | 493 W mean — **not capped** | **565 W mean, 567 max — `SW Power Cap: Active`** |
| SM clock | 2 665 MHz | **2 761 MHz** |
| utilisation | 100 % | 99 % |
| core temp | — | 76 °C (short run, not saturated) |

**A graphics load CAN drive this card into its power limit.** So the 493 W under
Superposition was the OpenGL path failing to extract full power from the GPU, not the
card's ceiling — exactly what the operator suspected, and the reason "100 % utilisation"
was a worthless indicator. Same card, 72 W and ~100 MHz apart, one reading capped and
one not.

⚠️ **Not yet a clean API A/B.** FurMark-Vulkan vs Superposition-OpenGL differs in *both*
workload and API — FurMark is a shader power-virus at 720p, Superposition a rendered
scene at 4K. **The controlled comparison is FurMark OpenGL vs FurMark Vulkan**, same
tool and scene, API as the only variable. That run is what would attribute the
Superposition score deficit to the OpenGL path rather than to something else.

## ✅ VERDICT 2026-08-04: this card performs NORMALLY. The 33 % deficit was an artefact.

**GravityMark 1.89, measured on this machine: score 85 647, 512.8 FPS** — Vulkan, Linux,
2560×1440, Temporal AA, 200 000 asteroids, Rasterization, single GPU, 167 s.

Compared against the leaderboard **filtered to identical settings** on both platforms
(filters are client-side JS — `set_platform()`, `set_api()`, `set_asteroids()` etc., so a
browser is required; the resulting URL is
`?api=vk&os=lnx&mode=one&gpu=nvidia`):

| Reference group (RTX 5090, single GPU, Vulkan, 2K, 200 K) | entries | this machine sits at |
|---|---|---|
| **Windows** — 87 637 / 87 013 / 86 946 / 83 093 / 82 887 | 5 | **98.5 % of median, 97.7 % of top** |
| **Linux** — 98 186 / 97 764 / 91 487 / 89 617 / 82 037 / 76 610 | 6 | **95.6 % of median, 87.2 % of top** — would rank 5th of 7 |

**Ray-tracing run, same settings plus `render=rt`: score 78 906, 472.5 FPS.** Relative
position is *better* than in rasterization:

| Reference group (RTX 5090, single GPU, **Vulkan RT**, 2K, 200 K) | entries | this machine |
|---|---|---|
| **Linux** — 88 908 / **78 906** / 76 274 / 72 606 / 71 999 | 4 + this | **2nd, 108.7 % of median**, 88.8 % of top |
| **Windows** — 90 866 / 77 542 | 2 | **101.8 % of median**, 86.8 % of top |

**Above median on both platforms under ray tracing**, against 5th-of-7 in rasterization —
so if anything this card is relatively stronger on the RT path. (Note `cachyos-test123`
at 76 274 again sits below this machine, on the same distro.)

**Level with Windows, mid-pack-to-above on Linux.** Nothing here indicates a hardware,
driver or configuration fault. The Superposition result was never evidence of one.

Two details worth keeping:
- The **#2 Linux entry (97 764) runs the same Ryzen 9 9950X3D**, so the ~12 % gap to it is
  not a CPU difference. Candidates: cooling (this card loses 2.5 MHz/°C — see above),
  background load, session compositing, or plain variance across six samples.
- A **CachyOS entry scored 82 037 — below this machine.** Same distro, lower result.

⚠️ **Sample sizes are tiny (6 and 5).** These are percentile positions in a handful of
self-submitted results, not a distribution. They rule out a large deficit; they cannot
resolve a few percent.

**And Linux is not behind here — it is ahead.** The top Linux score (98 186) exceeds the
top Windows score (87 637) by ~12 %. Combined with Basemark showing Linux+Vulkan above
Windows+DX12, the premise that a Linux 5090 should trail Windows has no support in either
corpus that labels OS and API.

### Methodology: a benchmark without a comparison corpus is a number, not a measurement

The 33 % deficit was only visible because a leaderboard existed. **A score in isolation
cannot detect underperformance** — this is the general lesson, not a Superposition
detail, and it applies to every benchmark in this repo.

Two ways to get a real reference:

**1. Within-machine A/B — self-contained, no external corpus needed.** Run the *same
workload* through two different APIs on the same card. A large gap identifies the render
path; a small gap moves suspicion back to the hardware. **FurMark 2 is the clean
instrument** because it ships both OpenGL and Vulkan modes — same scene, same machine,
one variable:

```sh
yay -S furmark
sudo ./tools/gpu-thermal.sh api-gl     -l none -t 240   # FurMark, OpenGL mode
sudo ./tools/gpu-thermal.sh api-vulkan -l none -t 240   # FurMark, Vulkan mode
```
Compare FPS **and** the power/clock traces. If Vulkan draws meaningfully more power and
clocks at the same voltage, OpenGL was leaving the card idle inside a "100 % utilised"
reading — which is exactly the trap that made the earlier 493 W figure misleading.

**2. External corpus that actually contains Linux results** — researched 2026-08-04:

| Tool | Corpus | RTX 5090 **Linux** entries |
|---|---|---|
| **Phoronix Test Suite** / OpenBenchmarking.org (AUR `phoronix-test-suite`) | large, ongoing, GPU-filterable | ✅ **confirmed present**, incl. a Unigine set (`2501310-PTS-UNIGINER91`) and gaming sets (`2501303-PTS-NVIDIAJA55`) |
| **GravityMark** ([leaderboard](https://gravitymark.tellusim.com/leaderboard/)) | ✅ every row carries `User \| Score \| FPS \| OS \| API \| GPU`, with filters for OS, API, GPU vendor, resolution, rendering mode. **Free**; `.run` self-installer. | ✅ **CONFIRMED by live browser-filtered read, 2026-08-04: Linux + RTX 5090 = 10 entries; Windows + RTX 5090 ≈ 45** (some dual-GPU). Filtering is client-side JS — a plain fetch cannot reach it, only a real browser. |
| Basemark GPUScore "Relic of Life" | cross-platform, OS+API labelled | ✅ Linux **and** Windows 5090 entries. **Linux+Vulkan 23 181 vs Windows+DX12 20 995** — Linux *ahead*, but that comparison confounds OS with API. |
| 3DMark | — | ❌ no Linux support |
| vkmark / glmark2 | on OpenBenchmarking | unconfirmed; scenes likely too light to load a 5090 |
| **Unigine's own leaderboard** | — | ⚠️ **Cannot determine whether it segments by OS/API at all** — pages render empty to a fetcher. **So the 47–53 k comparison group's platform is unknown**, and the 33 % deficit may be measured against Windows/DirectX systems. |

**Useful side finding — Vulkan is NOT handicapped on Windows.** GravityMark's Windows
RTX 5090 entries, read directly from the leaderboard 2026-08-04:

| API | scores |
|---|---|
| Vulkan | 188 638 · 162 452 · 149 268 |
| Direct3D12 | 162 500 · 160 202 |

They interleave, with the single highest result being **Vulkan**. So on Windows the two
paths are equivalent for this engine — which means **a Linux Vulkan result is fairly
comparable to a Windows one**, and the OpenGL-vs-DirectX confound that wrecked the
Superposition comparison does not apply to a Vulkan-based test. That is what makes
Vulkan the right API to standardise on for cross-platform comparison.

**PTS is the answer to "make it comparable"** — Linux-to-Linux, and no upload needed:
```sh
yay -S phoronix-test-suite
phoronix-test-suite benchmark 2501310-PTS-UNIGINER91   # runs yours against that published Linux result
phoronix-test-suite merge-results                       # purely local diff
```
Browsing and comparing require nothing to be uploaded; `upload-result` only publishes
*your* result into the public set.

⚠️ **There is NO trustworthy published figure for a "normal" Windows-vs-Linux RTX 5090
gap.** GamersNexus tested a 5090 on Bazzite Linux (Dec 2025) but states in the article
that it is **"not directly cross-comparable with our Windows testing"**. No rigorous
outlet has published a clean same-hardware delta. **Discard the "20 % Windows advantage"
and "95–99 % of Windows performance" figures in circulation** — traced 2026-08-04 to a
single low-credibility SEO page with no reviewer, methodology or citations. So there is
no reference value to judge a measured gap against; the corpora above are the substitute.

⚠️ **Provisional and load-bearing: ~33 % may be too large for an API effect alone.**
Measured same-machine Superposition OpenGL-vs-DirectX deltas run **~10–18 %** (Radeon VII
~18 %, RTX 3070 1080p Extreme ~10 %), and Phoronix reportedly found Superposition
*"basically identical"* between Windows and Linux when the API is held constant. If both
hold, roughly half the shortfall is unexplained and the hardware/config question is **not
closed**. **But this rests on a two-hop chain of sources that could not be read at
source** (phoronix.com returned 403 to every fetch; the figures come from search
snippets). Treat as a lead, not a finding — and note the local counter-evidence is
strong: FurMark Vulkan drove this card to `SW Power Cap: Active` at 565 W, which is not
the behaviour of underperforming hardware.

**What this means for the undervolt.** Two directions are open, both real:
- **More performance:** raise the frequency at 1.075 V toward the curve's 2 917 MHz.
  The card has ~80 W of unused power budget (493 of 575 W) to pay for it.
- **Less heat and noise:** get today's 2 665 MHz at ~1.00 V instead, cutting power at
  the same performance.

Not the "huge payoff" the power-limited case would have implied — the card is not
starved for power at gaming load — but a genuine, measurable win in either direction.

## RESULT: the undervolt ladder so far, and the setting to use (2026-08-04)

### ⚠️ RETRACTED: "+7.1 % score". The performance claim does not reproduce.

**The setting delivers the same performance at ~9.5 % less power. It is not faster.**
The ladder's score column below was measured as BLOCKS — four passes at one setting, then
four at the next, blocks compared across time — which charges any drift between them to
the setting. Run twice, hours apart, that design produced a claim and its own refutation:

| session | stock | 1000mV/3000 | conclusion |
|---|---|---|---|
| 16:28 | 76 896 | 82 329 | **+7.1 % — faster** |
| 19:14 | **82 244** | **79 531** | **−3.3 % — slower** |

Same setting, same card, delivered clock identical in all four runs (2802–2813 MHz, a
0.4 % spread) and GPU utilization flat at 92–93.5 %. The effect and the between-block
noise were the same size, so the SIGN of the result was decided by when it ran.

Settled by [`tools/gpu-ab-compare.sh`](../../../tools/gpu-ab-compare.sh) — stock and
setting interleaved within one session, counterbalanced ABBA so the within-run warming
trend cancels instead of landing on one arm:

| | n | score | power |
|---|---|---|---|
| setting | 3 | 78 842 | **328 W** |
| stock | 9 | 78 764 | **362 W** |
| **difference** | | **+0.10 %**, 95 % CI **[−0.10 %, +0.29 %]** | **−9.5 %** |

**Score: no measurable difference, and the interval is tight** — any true effect is under
±0.3 %. **Power: −9.5 %, and it reproduced in every session** (352→333, 366→327, 362→328).
Power was always the separable signal; score never was.

Consistent with the clock column, which nobody read: delivered clock is unchanged by this
setting. A setting that does not change the clock was never going to change the score.

⚠️ **This also killed the power argument for clock stretching below.** That argument used a
1.8 % power drop (333→327 W) — but `1000mV/3000` itself measured 333 W and 327 W in two
sessions with no setting change at all, so it rested on a difference smaller than the
noise. The *score* deficit at 3100 was 3.1 %, larger than the A/B noise band, so the
conclusion "3100 is not better" stands. The mechanism is now carried by the capped-regime
evidence instead, which is direct rather than inferential.

### The second payout: +4.1 % more work at the same 575 W

The A/B above measures the **coasting** regime, where GravityMark leaves the card ~200 W
below its limit. Pinned **at** the limit the same setting pays out in the other currency:
the power budget is fixed, so less voltage per MHz becomes throughput.

[`tools/gpu-capped-probe.sh`](../../../tools/gpu-capped-probe.sh), 2026-08-04, FurMark
Vulkan, 120 s per run, both runs rendering **2509×1371** and started at a matched
temperature (the tool waits for it):

| | stock | 1000 mV / 3000 | |
|---|---|---|---|
| frames delivered | 53 308 | 55 468 | **+4.1 %** |
| FPS avg | 444 | 462 | **+4.1 %** |
| FPS avg, repeat session | 443 | 459 | **+3.6 %** |
| power | 575 W | 575 W | capped, both |
| start → max temp | 45 → 87 °C | 46 → 87 °C | matched |
| **reported** core clock | 2 498 MHz | 2 312 MHz | **−7.4 %** ← see below |

An earlier run of the same probe gave **+2.7 %**, with the setting starting **34 °C
warmer**. At a fixed power cap a hotter card leaks more and buys less clock, so that run
was biased against the setting; removing the handicap moved the result to +4.1 %, in the
predicted direction and by a plausible amount. **The probe now matches start temperature
automatically** — that bias is a tool feature, not a thing to remember.

So the setting is worth having in **both** regimes: −9.5 % power when coasting, +4.1 %
work when capped. Nothing traded away in either.

⚠️ **The sweep is INCOMPLETE.** Planned anchors were `1000 950 900 875` mV; the
`950mV/3100` hard lock ended the run after **1000 and 950 only**. Everything below is the
best setting *among what was measured* — **900 and 875 mV were never tested**, and 950 mV
already showed the same score as 1000 mV for 17 W less, so the trend was still going the
right way when it stopped. Finishing it is a ready backlog item.

Walked with `tools/gpu-uv-explore.sh`; each rung a 4-pass `gpu-soak.sh` run
(GravityMark RT, 2560×1440, 200 k asteroids). Stock control measured **in the same
session**, not carried from earlier.

| rung | score | vs stock | reported MHz | watts | vs stock | verdict |
|---|---|---|---|---|---|---|
| stock | 76 896 † | — | 2 811 | 352 | — | control |
| 1000 mV / 2800 | 77 137 | +0.3 % | 2 749 | 342 | −2.8 % | pass |
| 1000 mV / 2900 | 79 560 | +3.5 % | 2 743 | 327 | −7.1 % | pass |
| **1000 mV / 3000** | 82 329 † | — | 2 802 | **333** | **−5.4 %** | **pass — chosen** |
| 950 mV / 3000 | 82 400 | +7.2 % | 2 781 | 316 | −10.2 % | pass |
| 1000 mV / 3100 | 79 778 | +3.7 % | 2 881 | 327 | −7.1 % | stable but **slower** |
| 950 mV / 3100 | — | — | — | — | — | 💥 **hard lock** |

† **Score columns are block measurements and are NOT comparable across rungs** — see the
retraction above. The power column is; it reproduced across three sessions.

**Both goals were achievable at once.** The chosen setting is faster *and* cooler than
stock on POWER. The "more performance vs less heat" tradeoff the
early analysis assumed turned out not to bind — flattening buys both, because stock was
spending voltage it did not need.

### Why 1000 mV / 3000 rather than 950 mV / 3000

Their scores are **statistically identical** (+0.1 %, against 2.4 % run-to-run spread),
so the 17 W is the only real difference — and it is bought with **stability margin**:

- At **950 mV**, the next rung up (3100) **hard-locked the whole machine.** 950/3000 sits
  directly beneath a hard failure.
- At **1000 mV**, the next rung up (3100) **completed four clean passes.** 1000/3000 has a
  proven-stable rung above it.

The standing rule is to settle one rung below the highest that passed. Only 1000/3000
satisfies it. 950 mV remains available if the 17 W ever matters more than the margin.

### ⚠️ Clock stretching: "it passed the soak" ≠ "it is better"

**1000 mV / 3100 is stable and slower.** Four passes, zero Xid, zero device-lost — and
3.1 % less score than the rung below it. The card reported a *higher* clock while
delivering *less* work:

| | 1000 mV/3000 | 1000 mV/3100 | |
|---|---|---|---|
| reported clock | 2 802 MHz | 2 881 MHz | **+2.8 %** |
| power | 333 W | 327 W | −1.8 % — *within noise, carries nothing* |
| FPS | 494.0 | 483.3 | −2.2 % |
| score | 82 329 | 79 778 | −3.1 % |

**The evidence is the capped-regime run, not this power column.** The original argument
here was "power tracks f·V², so a real +2.8 % clock must cost power and it did not" — but
`1000mV/3000` alone measured 333 W and 327 W across two sessions with nothing changed, so
that 1.8 % was noise. It is struck.

What replaces it is direct. Under FurMark at a fixed 575 W, same rendered size, matched
temperature, **stock reported 2 498 MHz and delivered 444 FPS while the setting reported
2 312 MHz and delivered 462 FPS.** FurMark is a fixed shader load, so throughput follows
the real core clock. A card genuinely running 7.4 % *slower* cannot deliver 4.1 % *more*
frames — the two readings are not measuring the same thing, and the high one is the one to
distrust. That is what "clock stretching" names: when the requested clock exceeds what the
voltage sustains, the GPU stretches the clock domain internally while `nvidia-smi` keeps
reporting the requested value. No crash, no Xid, no visual artifact, just quietly less
performance.

**Memory clock is ruled out — measured, not assumed.** It was the one alternative the
frames-track-core-clock inference could not exclude, and this card exposes five memory
states (405 / 810 / 7 001 / 13 801 / 14 001 MHz), so it was a candidate rather than a
constant. Sampled 2026-08-04 23:05: **14 001 MHz on all 40 loaded samples of both runs,
zero transitions.** `gpu-capped-probe.sh` samples `clocks.mem` every run and will refuse
the stretching conclusion outright if it moves.

**And the discrepancy is systematic, not a single reading.** Two independent sessions, each
temperature-matched, each deriving the real clock ratio from delivered frames:

| session | stock | setting | work | reported clock | implied over-report |
|---|---|---|---|---|---|
| 20:58 | 444 FPS | 462 FPS | +4.1 % | 2 498 → 2 312 MHz | **12.4 %** |
| 23:05 | 443 FPS | 459 FPS | +3.6 % | 2 500 → 2 307 MHz | **12.3 %** |

The stock arms agree to 0.2 %, so the baseline is stable and the spread lives in the setting
arm — the capped gain is **~3.9 %**, not 4.1. But the over-report lands within 0.1 % of
itself across two sessions. Noise does not reproduce to a tenth of a percent; a fixed
offset in what `nvidia-smi` reports does.

**Consequence for the method:** a stability soak cannot find the optimum on its own. The
useful ceiling is set by *score*, and it arrives **before** the crash — here a full 100 MHz
before it, at 1000 mV. Any rung must be judged on delivered score; reported clock is not
evidence, and at the top of the curve it actively lies.

**Ruled out as causes of the drop — measured, not assumed. Do not re-investigate:**

| Candidate | Why it is not the cause |
|---|---|
| vsync / refresh rate | run measured **483 FPS** against a 60 Hz panel — the cap never binds |
| display rearranged after the reboot | both panels 2560×1440; GravityMark logged the same rendered resolution in both runs |
| **operator alt-tabbed out repeatedly during the 3100 run** | no signature in the sensor series: **220 of 224 loaded samples in both runs**, utilization never below 91 % (mean **93.8 %** vs 93.5 % clean — slightly *higher*), and the only power dips are the four 1-sample pass boundaries present in both. A fullscreen benchmark on a secondary screen is never unmapped by the compositor, so it kept rendering at full rate. Residual compositor steal is bounded by that same 0.3-point utilization delta — **~0.3 % at most, against a 3.1 % loss** |

Method note worth keeping: **utilization + loaded-sample count is the cheap test for whether
a soak was disturbed.** An interrupted run shows a low-utilization tail; this one does not.

### 🔬 Open hypothesis: is the TOOL the limit at low anchors, or the silicon?

Stated so it can be killed. The FE guide's author claims his 0.890 V ceiling is the
**±1000 MHz-per-curve-point cap** that Afterburner and `nvcurve` both impose — that he
ran out of *tool*, not out of *card*, and that NVIDIA tunes the low-voltage curve points
for idle efficiency rather than at the silicon limit. Two AIB owners at 0.895–0.9 V /
2900 MHz are consistent with it.

**The anchor bases on this card**, read from its own curve — every delta below is
`target − base`, and all the ladder arithmetic depends on these four numbers:

| anchor | 1000 mV | 950 mV | 925 mV | 900 mV |
|---|---|---|---|---|
| base MHz | 2 737 | 2 572 | 2 347 | 2 002 |

⚠️ **The hypothesis is already partly refuted here — and by our own data.** At 900 mV,
`3000 MHz` is a delta of **+998**, comfortably inside the ±1000 tool cap. It was applied
on 2026-08-04 and the GPU faulted (Xid 38 → 109 → 154 PF FLR, compositor killed). So on
this card the tool cap is **not** what binds at 900 mV; something below +998 does.

What is actually established is a **bracket**, and it is wide:

| delta at the anchor | outcome |
|---|---|
| **+435** (`1000mV/3100`, base 2737 → +363; `950mV/3000`, base 2572 → +428) | ✅ passed |
| **+825** (the guide's `890mV/2827` target on this card's base) | ❓ **untested** |
| **+998** (`900mV/3000`) | ❌ faulted |

So the useful form of the question is not "does the tool bind?" — it doesn't — but
**where between +428 and +998 this card stops**. That is what the 925/900/890 sweep
measures, and it is worth measuring because the *distance* is large: the whole span
between a proven-good and a known-bad setting is unexplored.

**What would refute the conservative-curve reading outright:** rungs failing at low
anchors close to the already-proven delta — `900mV/2400` (+398) or `900mV/2500` (+498)
not passing. If those fail, the low-voltage points are not conservative on this sample and
the anchor walk should stop at 925 mV.

#### ✅ RESOLVED: 875 mV is unreachable, and 890 mV is the floor — arithmetic, not a test

The cap *does* bind, just not at 900 mV — it binds **below** it, because the stock curve
collapses faster than the cap allows you to climb. This card's own two anchors give the
slope: 2 002 MHz @ 900 mV, 2 347 @ 925 mV → **13.8 MHz per mV**. Extrapolating down, with
`+1000` as the ceiling any tool can ask for:

| anchor | est. base | base + 1000 = tool ceiling | can reach 2 827? |
|---|---|---|---|
| 900 mV | 2 002 | 3 002 | yes |
| **890 mV** | **1 864** | **2 864** | **yes — barely** |
| 880 mV | 1 726 | 2 726 | no |
| 875 mV | 1 657 | 2 657 | **no** |

So **`875 mV` — a planned anchor of the original sweep — was never reachable**, and its
"never tested" status is not an open question. Nothing below ~890 mV can hold a useful
clock through a ±1000 offset. Drop it from the ladder rather than scheduling it.

This independently reproduces the FE guide author's own floor: *"0.890 is the lowest
voltage which allows me to match stock speeds."* He hit it on his card; the same number
falls out of this card's curve slope. Corroborated from the other side by a Zotac 5090
owner at 0.865 V, whose vBIOS base is **1 407 MHz** — `+1000` caps him at 2 407 and he
[abandoned the attempt](https://forums.guru3d.com/threads/extend-core-offset-over-1000-rtx-5090.455803/)
because the limit is driver-level, not thermal or electrical. This card extrapolates to
1 519 → 2 519 at the same voltage: same wall, same mechanism.

±1000 MHz core is confirmed as the NvAPI-reported allowed range on a 5090
([LACT #936](https://github.com/ilya-zlobintsev/LACT/issues/936)) — the same number
Windows tools enforce, so it is not a `nvcurve` restriction to work around.

### The complete GPU crash record — and what it says about which load to test with

Every Xid this machine has ever logged, whole journal, all four retained boots
(`journalctl --no-pager | grep -i "xid"`, read 2026-08-04 23:30 — the instrument matters:
stacked `-b` flags do **not** union boots, the last one wins, and that form returned an
empty result that reads exactly like "no crashes"):

| when | Xid | process | cause |
|---|---|---|---|
| Aug 03 00:01–00:05 (×5) | 109 CTX SWITCH TIMEOUT + 31 MMU fault | `GameThread` — Marvel Rivals | **not the GPU setting** — `VKD3D_CONFIG=descriptor_heap`, root-caused and removed the same day ([marvel-rivals.md](../gaming/games/marvel-rivals.md)); card was at stock, no `nvcurve` call exists before Aug 04 10:58 |
| Aug 04 13:57 | 109 CTX SWITCH TIMEOUT | `GravityMark.x64` | undervolt ladder |
| Aug 04 17:37 | *(none — hard lock, died before logging)* | whole machine | `950mV/3100` |
| Aug 04 18:49 | 38, then 109, then 154 PF FLR | `gnome-shell` | mis-applied 900 mV flatten |

**FurMark has never crashed this card. Not once — and that is mechanism, not luck.**
FurMark pins 575 W, and the power cap *holds the clock down*: 2 307–2 500 MHz reported
(really ~12 % lower still, see stretching above). GravityMark coasts at ~362 W and boosts
to **2 802 MHz**. Undervolt instability is a high-clock-on-low-voltage failure, so the
load that pins the power limit is testing the card ~500 MHz *below* where it breaks.
**A power virus is a weak stability test for an undervolt** — the opposite of the natural
reading, and the same shape as the `gpu_burn` correction recorded above. Validate in the
coasting, high-boost regime: an uncapped framerate, not a stress test.

**Marvel Rivals is usable as the validation game, but read row 1 before blaming a crash on
the flatten.** Its five hangs carry the *same* Xid 109 signature our undervolt failures do,
and they were a launch-flag bug — so the row above is what stops a repeat from being
misattributed. Two known non-GPU-setting failure modes to keep straight while validating:
`descriptor_heap` (never re-add it) and the open Blackwell 3–5 s presentation freeze, which
is a stutter with **no Xid** and therefore distinguishable in the journal.

Method note, general: **a game only validates an undervolt if its own crash history has
been read and accounted for first** — and the whole-journal read is the load-bearing part.
Stacked boot flags (`-b -2 -b -1 -b 0`) do **not** union boots; the last one wins, silently,
and that form returns an empty result indistinguishable from a clean history. Use
`journalctl --no-pager | grep -i "xid"` with no `-b` at all.

### Apply it

```sh
sudo ./tools/gpu-flatten.sh --mv 1000 --mhz 3000     # apply
sudo ./tools/gpu-flatten.sh --reset                  # back to stock
```

**Not persistent — a reboot returns the card to stock.** No systemd unit is installed yet;
until one is, this is a per-boot command.

⚠️ **Validated against one fixed scene only.** GravityMark RT exercises a single shader
mix; a real game varies shaders, resolution and load in ways this does not. The 12-pass
confirmation run is still outstanding (the 950/3100 lock cut the session short).

## Open: case fans are driven by CPU temperature only

Under a GPU-only load the CPU stays idle, so a CPU-temperature fan curve has no
reason to ramp — precisely when case airflow is most needed. **Measured on this
machine: with the GPU at 575 W and the CPU idle, CPU Tctl rose from ~51 °C to
65–72 °C purely from case-air heat soak.** The fans did eventually reach 1 523 rpm,
but only *after* the GPU heat had soaked into the CPU — an indirect, lagging response
to the wrong sensor.

✅ **Confirmed available (2026-08-04):** the running `coolercontrold` already enumerates
the card as its own device — `GPU  NVIDIA GeForce RTX 5090` — alongside `CPU AMD Ryzen
9 9950X3D`, `Hwmon nct6799` (the fan channels), the NVMe drives and the DIMMs. So GPU
temperature is selectable as a fan-curve source today; nothing needs installing. A
**Mix profile** (max of CPU and GPU temperature) is the shape that fits: it keeps the
existing CPU behaviour and adds a GPU trigger, rather than trading one blind spot for
the other. Queried via the daemon's API at `localhost:11987`, per
[fan-control/coolercontrol-labels.md](../../../fan-control/coolercontrol-labels.md).

⚠️ Basis for the general recommendation is community consensus — no controlled study
was found — but the specific symptom above is measured here, not inherited from a forum.

## Verify

```sh
sudo ./tools/gpu-thermal.sh <label>        # GPU alone
sudo ./tools/gpu-thermal.sh <label> -c     # GPU + CPU together
nvidia-smi -q -d PERFORMANCE               # throttle reasons + lifetime counters
```
