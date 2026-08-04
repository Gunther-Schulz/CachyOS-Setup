# 9950X3D — ECO Mode 105 W + EXPO 6000 (applied)

**Machine:** Desktop.

Applied in one BIOS visit on 2026-08-04. Measured with
[`tools/cpu-bench.sh`](../../../tools/cpu-bench.sh); backlog and BIOS paths live in
[todo.md](../todo.md).

## What is set

| Setting | Value |
|---|---|
| Ai Overclock Tuner | EXPO I |
| Memory Frequency | DDR5-6000 (kit `CMH64GX5M2D6000Z40`, 2×32 GB dual-rank) |
| Timings / voltages | 40-50-50-96, VDD/VDDQ 1.35 V |
| ECO Mode | **105 W** (→ 142 W PPT) |
| Precision Boost Overdrive | Advanced (limits Auto) |
| Curve Optimizer | **not set** — all cores still at 0 |

## Measured effect

Both runs: 32 threads, `powersave` / `balance_performance` / `amd-pstate-epp`,
GNOME power mode `balanced`, 3 × 60 s, medians.

| Multicore (`--matrix 0`) | stock | ECO+EXPO | Δ |
|---|---|---|---|
| bogo-ops/s | 116 500 | 102 101 | **−12.4 %** |
| package power | 199.4 W | **142.0 W** | **−28.8 %** |
| sustained clock | 4 952 MHz | 4 325 MHz | −12.7 % |
| **efficiency** | 584 bogo/W | **719 bogo/W** | **+23.1 %** |

| Single-thread (`--cpu 1 fft`) | stock | ECO+EXPO | Δ |
|---|---|---|---|
| bogo-ops/s | 5 047 | 5 066 | +0.4 % (noise) |
| package power | 59.6 W | 55.4 W | −7.0 % |
| sustained clock | 5 368 MHz | 5 360 MHz | −0.2 % |

## What this establishes

**ECO Mode is genuinely binding, and PBO `Advanced` does not override it.** Package
power pinned at **142.0 W on all three multicore runs** — that flatness is the PPT
limiter clamping, not a coincidence, and 142 W is exactly the 105 W TDP tier's PPT.
This was the open question when both were set in the same visit.

**Single-thread is untouched**, as designed: ECO caps sustained package power, and one
core boosting never approaches that ceiling. This is also why ECO was never going to
quieten the fans — see the fan-surge item in [todo.md](../todo.md).

**The performance cost is larger than planned.** The work was scoped around "the last
~100 W buys a few percent"; the real multicore cost is **12.4 %**. The clock drop
(−12.7 %) tracks it almost exactly, so this is a plain frequency reduction under the
power cap, nothing stranger. Still a good trade — a 29 % power cut for a 12 % loss is
**+23 % perf/watt** — but "a few percent" was wrong and the number to quote is 12 %.

⚠️ **These two settings are not separable from this data.** The stock baseline ran at
4800 MT/s and this one at 6000, so the delta is ECO *and* EXPO together. EXPO can only
help multicore throughput, so **the ECO-only cost is ≥ 12.4 %**, not less. To separate
them, run a third pass with ECO returned to Auto and EXPO left on; EXPO's contribution
then falls out by subtraction, and EXPO does not have to be sacrificed to get it.

## Verify

```sh
sudo ./tools/cpu-bench.sh <label>          # writes ~/bench/<label>/
diff ~/bench/stock/conditions.txt ~/bench/eco-expo/conditions.txt
```

The `conditions.txt` diff is the guard that matters: it catches a power-mode or
RAM-speed change between runs, which is the failure that silently invalidates a
before/after comparison. It is what caught the 4800 → 6000 confound above.

## Undo

BIOS → `Ai Tweaker → Ai Overclock Tuner` = Auto (drops EXPO), and
`Advanced → AMD Overclocking → AMD Overclocking → Precision Boost Overdrive → ECO Mode`
= Auto. Neither can damage anything: ECO is a *lower* power ceiling, so it strictly
improves electrical and thermal margin.
