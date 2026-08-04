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

**Level with Windows, mid-pack on Linux.** Nothing here indicates a hardware, driver or
configuration fault. The Superposition result was never evidence of one.

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
