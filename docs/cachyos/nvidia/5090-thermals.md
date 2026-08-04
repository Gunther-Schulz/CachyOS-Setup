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

## Open: case fans are driven by CPU temperature only

Under a GPU-only load the CPU stays idle, so a CPU-temperature fan curve has no
reason to ramp — precisely when case airflow is most needed. **Measured on this
machine: with the GPU at 575 W and the CPU idle, CPU Tctl rose from ~51 °C to
65–72 °C purely from case-air heat soak.** The fans did eventually reach 1 523 rpm,
but only *after* the GPU heat had soaked into the CPU — an indirect, lagging response
to the wrong sensor.

`coolercontrol` can drive a curve from GPU temperature, or from a CPU/GPU mix. Worth
doing on mechanism alone; it costs nothing and targets the measured lag. ⚠️ Basis for
the general recommendation is community consensus — no controlled study was found —
but the specific symptom above is measured here, not inherited from a forum.

## Verify

```sh
sudo ./tools/gpu-thermal.sh <label>        # GPU alone
sudo ./tools/gpu-thermal.sh <label> -c     # GPU + CPU together
nvidia-smi -q -d PERFORMANCE               # throttle reasons + lifetime counters
```
