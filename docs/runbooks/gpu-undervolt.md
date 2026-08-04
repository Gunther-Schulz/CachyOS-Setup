# Runbook — NVIDIA GPU undervolt by V/F flatten

**Machine:** Any NVIDIA card `nvcurve` supports (tested: RTX 5090 Blackwell, driver
610.43.03). Written for a fresh context — no prior session knowledge assumed.

**Goal:** more performance *and* less heat, by making the card do the same work at a lower
voltage. Not a tradeoff — on the 5090 this delivered +7.1 % score for −5.4 % power.

---

## What a flatten is

Pick an **anchor voltage**, set the frequency there, and pin every *higher*-voltage point
to that same frequency. The card gains nothing by going past the anchor, so it stops
there — the curve becomes a **voltage ceiling**. Points below the anchor are untouched, so
idle behaviour is unchanged.

This is not a global offset. A global offset raises the whole curve including the top,
which is how a `+400` attempt hung this machine (top point pushed to 3 580 MHz @ 1 240 mV).

A setting is a **pair**: `(anchor mV, target MHz)`.

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

The report ranks by **score**, and that is the point of the whole exercise:

| Tag | Meaning |
|---|---|
| `WINS BOTH  [margin proven]` | faster *and* cooler, **and** a higher rung at the same anchor passed |
| `WINS BOTH  [top rung — no margin above]` | faster and cooler, but sitting at the edge |
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
| power | 333 W | 327 W | **−1.8 %** ← should have RISEN |
| score | 82 329 | 79 778 | **−3.1 %** |

Power goes as f·V². At a fixed voltage ceiling a real clock increase *must* cost power. It
didn't — so the effective clock was below the reported one.

**Therefore: a stability soak cannot find the optimum.** The useful ceiling is set by score
and arrives *before* the crash — a full 100 MHz before it, here. The tools detect this
automatically and stop; you do not have to spot it.

### Which rung to actually run

Prefer a rung with a **passing rung above it at the same anchor** — that margin is
*measured*, not assumed. Only when nothing above it passed do you back off one rung, and
that backed-off rung is untested by definition.

Worked example from the 5090: `950mV/3000` scored *higher* (82 400 vs 82 329) but
`950mV/3100` **hard-locked the machine**, so it sits directly beneath a hard failure.
`1000mV/3000` had `1000mV/3100` pass above it. Statistically tied on score (0.1 %, against
2.4 % run-to-run spread), so the margin decides. The report does this reasoning for you.

---

## Apply and keep

```fish
sudo ./tools/gpu-flatten.sh --mv 1000 --mhz 3000     # apply the chosen pair
sudo ./tools/gpu-flatten.sh --reset                  # back to stock
```

Before trusting it daily:

1. **12-pass soak** — `sudo ./tools/gpu-soak.sh --screen 1 --passes 12`
2. **~1 h of a real game.** One fixed benchmark scene is one shader mix, not a workload.
   Check `journalctl -b | grep -i xid` afterwards.
3. Only then make it persistent (nvcurve profile → systemd unit).

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
./tools/test-gpu-uv-selection.sh    # 11 cases, no root, no GPU, ~1 s
```

Run it after touching `gpu-uv-explore.sh`. It pins the selection rule and the
clock-stretch detector against fixtures, and it extracts the live code rather than
restating it, so it cannot pass while the script drifts underneath it.

---

## Machine-specific results

This repo's 5090: [`../cachyos/nvidia/5090-thermals.md`](../cachyos/nvidia/5090-thermals.md)
— full ladder table, the curve read off the card, and the thermal baseline.
