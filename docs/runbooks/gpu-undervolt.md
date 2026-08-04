# Runbook — NVIDIA GPU undervolt by V/F flatten

**Machine:** Any NVIDIA card `nvcurve` supports (tested: RTX 5090 Blackwell, driver
610.43.03). Written for a fresh context — no prior session knowledge assumed.

**Goal:** the same work at a lower voltage — less power and heat for equal performance.
On the 5090 this delivered **−9.5 % power at unchanged performance** when coasting, and
**~+3.9 % more work at the same wattage** when power-capped — both regimes, nothing traded.

⚠️ **Do not claim a performance gain from block comparisons.** Measuring four passes at
one setting, then four at the next, charges any drift between the blocks to the setting.
On this card that produced +7.1 % at 16:28 and −3.3 % at 19:14 for the SAME setting, with
delivered clock identical to 0.4 % in all four runs. Any performance claim needs
[`gpu-ab-compare.sh`](../../tools/gpu-ab-compare.sh), which interleaves the arms within
one session. Power is separable and survives block comparison; score is not and does not.

---

## What a flatten is

Pick an **anchor voltage**, set the frequency there, and pin every *higher*-voltage point
to that same frequency. The card gains nothing by going past the anchor, so it stops
there — the curve becomes a **voltage ceiling**. Points below the anchor are untouched, so
idle behaviour is unchanged.

This is not a global offset. A global offset raises the whole curve including the top,
which is how a `+400` attempt hung this machine (top point pushed to 3 580 MHz @ 1 240 mV).

A setting is a **pair**: `(anchor mV, target MHz)`.

### The MHz is a ceiling, not a demand — and the mV is the real setting

The frequency is **not** being locked on. Nothing forces the card to run at it. The curve
still says "at voltage V you may run at most F", and the card still picks its own operating
point every millisecond based on power, temperature and load — it idles, it drops under a
power cap, it does all of that unchanged. What the flatten does is make the answer to
"may I run faster?" stop improving above the anchor voltage. The card then has no reason to
raise voltage past it, so it doesn't.

So of the pair, **the mV is the setting you are choosing** — the voltage you refuse to
exceed. The MHz only says *what you demand in exchange*: how much clock the card must
deliver at that voltage for the deal to be worth taking. Ask too much and it does not
refuse — it stretches (below), or it hangs. Both numbers move together: at a given anchor,
the highest MHz that still delivers is the card's real limit at that voltage.

---

## Prerequisites

```fish
uv tool install nvcurve
sudo nvcurve setup          # only continue if it prints "Compatible"
```

`nvcurve setup` is **not** purely read-only — it writes +5 MHz to one point, reads it back,
and restores a snapshot. `nvcurve read` *is* read-only.

GravityMark is the load: <https://gravitymark.tellusim.com/> (free `.run` installer).
The soak finds it automatically, or set `GRAVITYMARK=/path/to/GravityMark.x64`.

---

## Run it

```fish
sudo ./tools/gpu-uv-explore.sh --screen 1     # ~3-4 h unattended; Ctrl-C is a safe pause
sudo ./tools/gpu-uv-explore.sh --resume       # continue, re-running nothing already decided
./tools/gpu-ladder-report.sh --state ~/bench/explore-latest.tsv    # progress, NO root
```

`--screen 1` puts the benchmark on a second monitor so the primary stays usable. **Tabbing
away does not disturb it** — the compositor never unmaps a fullscreen window, and the soak
now verifies this per run and says so.

The ladder (anchor voltages and target clocks) is **derived from the card's own V/F curve**
and printed before the sweep starts. Override with `--anchors` / `--clocks` only if you
know the card better than its curve does.

**Nothing here persists.** A reboot returns the card to stock, always. That is the safety
property the whole procedure rests on.

---

## Reading the result

The report ranks by **score**, because reported clock lies (see STRETCHED below). But read
the score column knowing what it is: a BLOCK measurement, good enough to reject a rung that
is clearly worse, **not** good enough to claim a few percent gain. For that, see the
warning at the top.

| Tag | Meaning |
|---|---|
| `WINS BOTH  [margin proven]` | at least as fast, less power, **and** a higher rung at the same anchor passed |
| `WINS BOTH  [top rung — no margin above]` | at least as fast and cooler, but sitting at the edge |
| `STRETCHED` | **reports a higher clock and delivers less work** — see below |
| `trade: X% score for Y% power` | slower, but cheaper |

### The one counter-intuitive result: STRETCHED

A rung can pass a 4-pass soak with **zero Xid, zero device-lost, no artifacts** and still be
the wrong setting. When the requested clock exceeds what the anchor voltage sustains, the
GPU **stretches the clock domain internally** while `nvidia-smi` keeps reporting the value
you asked for.

Measured on the 5090 at `1000mV/3100` against `1000mV/3000`:

| | 3000 | 3100 | |
|---|---|---|---|
| reported clock | 2 802 MHz | 2 881 MHz | **+2.8 %** |
| power | 333 W | 327 W | −1.8 % — *noise, see below* |
| score | 82 329 | 79 778 | **−3.1 %** |

⚠️ **Do not argue stretching from power.** A −1.8 % power reading is inside the
session-to-session noise band, and that is what the original version of this argument used.
What holds is the *score* deficit, −3.1 %, larger than the interleaved A/B noise band
(±0.3 %) — so **the higher rung is not better**.

**The clean test for stretching is a power-capped fixed-shader load**, which
[`gpu-capped-probe.sh`](../../tools/gpu-capped-probe.sh) runs. Under a hard power cap,
throughput follows the *real* core clock. If the card reports a **lower** clock while
delivering **more** frames — same render size, same wattage, matched start temperature,
memory clock unchanged — then the two clock readings are not measuring the same thing and
the higher one is the false reading. That is a contradiction, not an inference from a
power model, and the probe checks every one of those conditions before it will say so.
This card's numbers: [`../cachyos/nvidia/5090-thermals.md`](../cachyos/nvidia/5090-thermals.md).

**What survives regardless: a stability soak cannot find the optimum.** A rung can pass
every stability check and still deliver less work, so the useful ceiling is set by score and
arrives *before* the crash — a full 100 MHz before it, here. The tools detect this and stop.

### Which rung to actually run

Prefer a rung with a **passing rung above it at the same anchor** — that margin is
*measured*, not assumed. Only when nothing above it passed do you back off one rung, and
that backed-off rung is untested by definition.

Worked example from the 5090: `950mV/3000` scored *higher* (82 400 vs 82 329) but
`950mV/3100` **hard-locked the machine**, so it sits directly beneath a hard failure.
`1000mV/3000` had `1000mV/3100` pass above it. Tied on score within the noise, so the margin
decides — which is the right way round: **margin is a stability fact, score at this
resolution is not a fact at all.** The report does this reasoning for you.

---

## Measuring the setting honestly

Two tools, because the ladder answers neither question well:

```fish
sudo ./tools/gpu-ab-compare.sh --mv 1000 --mhz 3000     # is it faster? (~35 min)
sudo ./tools/gpu-capped-probe.sh --mv 1000 --mhz 3000   # does it help when power-capped? (~4 min)
```

`gpu-ab-compare.sh` interleaves stock and setting within one session, counterbalanced ABBA,
and reports a paired difference with a confidence interval. It is the only thing here that
can support a coasting performance claim.

`gpu-capped-probe.sh` measures the other regime — pinned at the power limit, where the
payout is throughput rather than watts. It waits for a **matched starting temperature**
before each run (a hotter card buys less clock inside a fixed budget, and an unmatched
first measurement here understated the gain by a third), verifies both runs rendered at the
same size, samples memory clock, and reads its verdict off **FPS, never reported clock**.

---

## Apply and keep

```fish
sudo ./tools/gpu-flatten.sh --mv 1000 --mhz 3000     # apply the chosen pair
sudo ./tools/gpu-flatten.sh --reset                  # back to stock
```

Before trusting it daily:

1. **12-pass soak** — `sudo ./tools/gpu-soak.sh --screen 1 --passes 12`
   (stability only — 12 passes of one scene is not evidence about performance)
2. **~1 h of a real game.** One fixed benchmark scene is one shader mix, not a workload.
   Check `journalctl -b | grep -i xid` afterwards — **and pick the title by the two rules
   below.**
3. Only then make it persistent (nvcurve profile → systemd unit).

### Choosing the validation load — two rules, both learned by getting them wrong

⚠️ **A power virus is a weak stability test for an undervolt.** FurMark, `gpu_burn` and
anything else that pins the power limit holds the clock *down* — on the 5090, ~2 400 MHz
against ~2 800 MHz for a coasting load. Undervolt instability is a high-clock-on-low-voltage
failure, so the heaviest-looking load tests the card hundreds of MHz below where it breaks.
Validate in the **coasting, high-boost** regime: an uncapped framerate, not a stress test.
(Confirmed twice on this card: `gpu_burn` ran clean at an offset that froze the machine in
GravityMark, and FurMark has never produced a single Xid across the whole tuning campaign.)

⚠️ **Read the machine's crash history BEFORE the run, not after it crashes.** A GPU hang
presents as Xid 109 whatever caused it — a bad Proton flag, a driver bug and a too-low
voltage are the same line in the journal. Unless the title's existing faults are known and
accounted for, the first crash gets charged to the setting and the ladder backs off a rung
for no reason. A title with prior hangs is still usable *if* each one is root-caused; what
disqualifies it is an **unexplained** hang.

```fish
journalctl --no-pager | grep -i xid
```

**Read that command carefully — it has no `-b`.** Stacked boot flags (`-b -2 -b -1 -b 0`)
do *not* union boots: the last one wins, silently, and the result reads exactly like a
clean history. That mistake here hid five stock crashes and produced a confident wrong
recommendation. Search the whole journal, then read the `name=` field on every hit.

---

## When it goes wrong

| Symptom | Meaning | Action |
|---|---|---|
| Machine hard-locks | that pair is past the silicon | reboot (card returns to stock); `--resume` and answer **`y`** when asked whether it crashed |
| `Xid` in the journal | shader hang — the real failure mode | back off one rung; it is not an artifact you can see |
| `INCONCLUSIVE` verdict | the benchmark never ran | a launch failure, **not** instability — check the log before concluding anything |
| `⚠️ DISTURBED RUN` | 12 s+ below 80 % utilization | something else had the machine; scores are not comparable, re-run |
| Report says `stock reference: NONE` | no baseline rung in this ladder | run the sweep from the start; do not compare against another card or another day |

**The one thing that cannot be automated** is recovery from a hard lock. The state file is
synced before every attempt, so `--resume` knows exactly which pair did it — but the
machine has to be brought back by hand.

---

## Verify the tools themselves

```fish
./tools/test-gpu-uv-selection.sh    # 20 cases, no root, no GPU, ~1 s
```

Run it after touching `gpu-uv-explore.sh` or `gpu-flatten.sh`. It pins the selection rule,
the clock-stretch detector, the proven-delta cap and flatten idempotency against fixtures,
and it extracts the live code rather than restating it, so it cannot pass while the script
drifts underneath it.

---

## Machine-specific results

This repo's 5090: [`../cachyos/nvidia/5090-thermals.md`](../cachyos/nvidia/5090-thermals.md)
— full ladder table, the curve read off the card, and the thermal baseline.
