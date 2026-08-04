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

### The catch: on Linux, "undervolt" is built FROM the power limit

NVIDIA does not expose a V/F curve editor on Linux — that is Afterburner on Windows.
What exists here (confirmed on driver 610.43.03):

- `GPUGraphicsClockOffsetAllPerformanceLevels`, range **−1000 … +1000** MHz
- `nvidia-smi -pl`, range **400–600 W**

The standard Linux undervolt is **both together**: cap power so the card selects a
lower point on its V/F curve, then apply a **positive** clock offset to recover the
clocks lost at that lower voltage. Net effect — near the original performance at
meaningfully less voltage and heat.

**A power-limit cut alone is not an undervolt**, it is just less power, and it costs
performance proportionally. **A positive offset alone is an overclock** and makes heat
worse. Declining the power limit therefore removes the mechanism rather than avoiding a
downside; what remains is a *negative* clock offset, which lowers voltage only by
running the card slower — strictly worse than the two-part technique at the same
performance.

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
