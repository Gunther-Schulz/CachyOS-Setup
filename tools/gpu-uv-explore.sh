#!/usr/bin/env bash
# gpu-uv-explore.sh — unattended overnight sweep of BOTH axes, with the analysis built in.
#
# THE SETTING IS A PAIR: (anchor voltage, target clock). Every earlier tool here walked
# one axis with the other frozen at a guessed value, which is why none of them could
# answer the question on its own. This walks both and reports the frontier.
#
# IT IS NOT A GRID. Lower voltage can never hold MORE clock, so once the maximum at one
# anchor is known, the next (lower) anchor starts THERE and walks DOWN until it passes —
# typically one or two rungs instead of five. A naive grid would be ~20 rungs and 7 h;
# this is usually 8-10 rungs and 3-4 h.
#
# ALGORITHM
#   0. baseline at stock, in this same session (every broken comparison in this repo
#      came from a control measured under different conditions)
#   1. at the first anchor, climb the clock until a rung FAILS -> that anchor's maximum
#   2. at each lower anchor, start from the previous maximum and walk DOWN to the first
#      rung that PASSES -> that anchor's maximum
#   3. stop early if an anchor cannot hold even --floor MHz (that voltage is too low)
#   4. print the frontier and pick the winner, applying the back-off-one-rung rule
#
# WHAT CANNOT BE AUTOMATED: recovery from a HARD hang. If a rung locks the machine, the
# run ends there. The state file is synced before every attempt, so `--resume` reports
# which pair did it — but the remaining rungs need a re-run. Anchors are therefore
# ordered most-informative-first, so an overnight hang still leaves useful data.
#
# Usage:
#   sudo ./tools/gpu-uv-explore.sh --screen 1
#   sudo ./tools/gpu-uv-explore.sh --screen 1 --anchors "1000 950 900" --passes 6
#   sudo ./tools/gpu-uv-explore.sh --resume     # CONTINUE after Ctrl-C or a hang
#   ./tools/gpu-uv-explore.sh --status          # report only, change nothing
#   sudo ./tools/gpu-uv-explore.sh --dry-run    # show the derived ladder, write nothing
#   ./tools/gpu-ladder-report.sh --state ~/bench/explore-state.tsv

set -uo pipefail
export LC_ALL=C

# Anchors and clocks are DERIVED FROM THE CARD'S OWN V/F CURVE unless given explicitly.
# They were hardcoded to this machine's 5090 (1000-875 mV, 2800-3200 MHz), which silently
# made the tool useless on any other GPU: on a laptop card those voltages sit above the
# curve's top and every rung would be refused, or worse, clamped into nonsense. A ladder's
# rungs are a property of the card, so the card is what supplies them.
ANCHORS=""          # empty = derive; --anchors overrides
CLOCKS=""           # empty = derive; --clocks overrides
FLOOR=0             # 0 = derive (the lowest clock in the list)
PASSES=4            # SCREENING passes per rung (~11 min) — cheap enough to sweep widely
CONFIRM=12          # passes for the final winner only (~33 min) — the run that decides
SCREEN=0
WINDOWED=""
RESUME=0
STATUS=0
DRYRUN=0

usage() { sed -n '2,34p' "$0"; exit "${1:-0}"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --anchors) ANCHORS=$2; shift 2 ;;
    --clocks) CLOCKS=$2; shift 2 ;;
    --floor) FLOOR=$2; shift 2 ;;
    --passes) PASSES=$2; shift 2 ;;
    --confirm) CONFIRM=$2; shift 2 ;;
    --screen) SCREEN=$2; shift 2 ;;
    --windowed) WINDOWED="--windowed"; shift ;;
    --resume) RESUME=1; shift ;;
    --status) STATUS=1; shift ;;
    --dry-run) DRYRUN=1; shift ;;
    -h|--help) usage 0 ;;
    *) echo "unknown option: $1" >&2; usage 1 ;;
  esac
done

home=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)
HERE="$(cd "$(dirname "$0")" && pwd)"
FLATTEN="$HERE/gpu-flatten.sh"; SOAK="$HERE/gpu-soak.sh"
[ -x "$FLATTEN" ] && [ -x "$SOAK" ] || { echo "gpu-flatten.sh / gpu-soak.sh missing" >&2; exit 1; }
NVCURVE="$home/.local/bin/nvcurve"
STATE_DIR="${home}/bench"
mkdir -p "$STATE_DIR"
LATEST="$STATE_DIR/explore-latest.tsv"

# A run is UNFINISHED unless it wrote its completion marker. Checking for that is more
# honest than inferring from the last line — a run killed between rungs looks tidy.
# grep does not interpret \t, so '^SWEEP\tCOMPLETE' matched nothing and every run —
# finished or not — was offered for resume. Match the field with awk instead.
unfinished() { [ -f "$1" ] && ! awk -F'\t' '$1=="SWEEP" && $2=="COMPLETE"{f=1} END{exit !f}' "$1"; }
newest_unfinished() {
  local f
  for f in $(ls -t "$STATE_DIR"/explore-*.tsv 2>/dev/null); do
    [ "$f" = "$LATEST" ] && continue
    unfinished "$f" && { echo "$f"; return; }
  done
}

PRIOR=$(newest_unfinished)

# ── --status: report only, change nothing ───────────────────────────────────────────
if [ "$STATUS" = 1 ]; then
  STATE=${STATE:-${PRIOR:-$(ls -t "$STATE_DIR"/explore-*.tsv 2>/dev/null | grep -v latest | head -1)}}
  [ -f "$STATE" ] || { echo "no run found in $STATE_DIR" >&2; exit 1; }
  echo "run: $STATE"; echo
  exec "$HERE/gpu-ladder-report.sh" --state "$STATE"
fi

# Root is needed to WRITE curve edits. --status only reads, so the check lives here,
# below the status branch — it sat above it before, gating a read-only operation.
[ "$(id -u)" -eq 0 ] || { echo "needs root (applies curve edits); re-run with sudo" >&2; exit 1; }

# ── derive the ladder from THIS card's V/F curve ─────────────────────────────────────
# The fractions below are the only tuned constants, and they are read off the shape of a
# boost curve rather than off this particular card:
#
#   anchors 0.85 -> 0.70 of the curve's top voltage. Above ~0.85 there is nothing to win —
#     that is where the card already runs. Below ~0.70 the frequency the curve offers has
#     collapsed far enough that no realistic flatten holds it, so rungs there only cost
#     time and crashes. 50 mV steps: finer than the run-to-run noise can resolve in one
#     overnight sweep.
#   clocks 0.88 -> 1.01 of the curve's top frequency, in 100 MHz steps. The top end goes
#     slightly PAST the curve maximum on purpose: a flatten's whole point is to reach a
#     clock the stock curve only offers at a higher voltage.
#
# Sanity check on this machine's 5090 (curve top 1240 mV / 3180 MHz): derives
# 1050/1000/950/900 mV and 2800/2900/3000/3100/3200 MHz — clocks IDENTICAL to the
# hand-picked ladder and anchors overlapping on three of four (it adds a safer 1050 first
# rung and drops 875). Reproducing the manual choice from the curve alone is the evidence
# that this is a rule and not a fit to one card.
derive_ladder() {
  local json
  json=$("$NVCURVE" read --json 2>/dev/null) || return 1
  echo "$json" | python3 -c '
import json,sys
d=json.load(sys.stdin)
pts=[p for p in d["vf_curve"] if p.get("domain")=="gpu" and p["volt_uV"]>0]
if not pts: sys.exit(1)
volts=sorted({p["volt_uV"]/1000.0 for p in pts})
vmax=volts[-1]; fmax=max(p["freq_kHz"] for p in pts)/1000.0
def snap(v): return min(volts, key=lambda x: abs(x-v))
anchors=[]
v=round(vmax*0.85); lo=vmax*0.70
while v>=lo:
    s=int(round(snap(v)))
    if s not in anchors: anchors.append(s)
    v-=50
clocks=[]
c=int(round(fmax*0.88/100)*100); hi=fmax*1.01
while c<=hi:
    clocks.append(c); c+=100
if not anchors or not clocks: sys.exit(1)
print(" ".join(str(a) for a in anchors))
print(" ".join(str(c) for c in clocks))
print("%.0f %.0f" % (vmax, fmax))
'
}

if [ -z "$ANCHORS" ] || [ -z "$CLOCKS" ]; then
  if DERIVED=$(derive_ladder); then
    D_ANCHORS=$(echo "$DERIVED" | sed -n 1p)
    D_CLOCKS=$(echo "$DERIVED" | sed -n 2p)
    D_TOP=$(echo "$DERIVED" | sed -n 3p)
    [ -z "$ANCHORS" ] && ANCHORS=$D_ANCHORS
    [ -z "$CLOCKS" ] && CLOCKS=$D_CLOCKS
    echo "derived from this card's V/F curve (top ${D_TOP% *} mV / ${D_TOP#* } MHz):"
    echo "  anchors: $ANCHORS mV"
    echo "  clocks:  $CLOCKS MHz"
    echo "  override with --anchors / --clocks if you know better for this card."
  else
    echo "Could not read the V/F curve, so the ladder cannot be derived." >&2
    echo "  Check:  sudo $NVCURVE read --json" >&2
    echo "  Or supply them yourself:  --anchors \"1000 950 900\" --clocks \"2800 2900 3000\"" >&2
    exit 1
  fi
fi
[ "${FLOOR:-0}" -gt 0 ] || FLOOR=$(echo "$CLOCKS" | tr ' ' '\n' | sort -n | head -1)

# --dry-run: show the ladder and stop. An overnight sweep is a big commitment to make on
# faith, and the derivation above is the part most likely to be wrong on an unfamiliar
# card — a ladder whose clocks are nonsense should be visible in a second, not at 3 a.m.
if [ "$DRYRUN" = 1 ]; then
  echo
  echo "=== DRY RUN — nothing will be written to the GPU ==="
  echo "anchors: $ANCHORS mV"
  echo "clocks:  $CLOCKS MHz"
  echo "floor:   $FLOOR MHz  (an anchor that cannot hold this ends the sweep)"
  echo "passes:  $PASSES screening / $CONFIRM confirming"
  echo
  echo "Worst case it walks every rung:"
  na=$(echo "$ANCHORS" | wc -w); nc=$(echo "$CLOCKS" | wc -w)
  echo "  $na anchors x $nc clocks = $(( na * nc )) rungs, ~$(( na * nc * PASSES * 167 / 3600 )) h"
  echo "  In practice far fewer: lower anchors start at the previous maximum and walk"
  echo "  DOWN to the first rung that passes, and the stop rules end a climb early."
  echo
  echo "Sanity-check the clocks against what the card actually runs at stock:"
  echo "  nvidia-smi --query-gpu=clocks.max.sm --format=csv"
  exit 0
fi

BASE_DONE=0
declare -A ANCHOR_MAX ANCHOR_DONE

if [ "$RESUME" = 1 ]; then
  STATE=$PRIOR
  [ -n "$STATE" ] || { echo "no unfinished run to resume in $STATE_DIR" >&2; exit 1; }
  echo "resuming: $STATE"
elif [ -n "$PRIOR" ]; then
  # Running fresh over an unfinished run would DESTROY it. Ask, rather than assume.
  echo "⚠️  An unfinished run exists:"
  echo "     $PRIOR"
  "$HERE/gpu-ladder-report.sh" --state "$PRIOR" 2>/dev/null | head -8 | sed 's/^/     /'
  echo
  echo "  [r] resume it   [n] start a NEW run (the old one is kept, not deleted)   [a] abort"
  printf '  choice: '
  read -r choice < /dev/tty
  case "${choice:-a}" in
    r|R) RESUME=1; STATE=$PRIOR; echo "  resuming $STATE" ;;
    n|N) STATE="$STATE_DIR/explore-$(date +%Y%m%d-%H%M%S).tsv"; echo "  new run: $STATE" ;;
    *)   echo "  aborted — nothing changed."; exit 0 ;;
  esac
else
  STATE="$STATE_DIR/explore-$(date +%Y%m%d-%H%M%S).tsv"
fi

ln -sfn "$STATE" "$LATEST"
say() { echo "$*" | tee -a "${STATE%.tsv}.log"; sync; }

if [ "$RESUME" = 1 ]; then
  while IFS=$'|' read -r label verdict; do
    [ "$label" = "stock" ] && { [ "$verdict" = "PASS" ] && BASE_DONE=1; continue; }
    mv=${label%%mV/*}; mhz=${label##*/}
    if [ "$verdict" = "PASS" ]; then
      cur=${ANCHOR_MAX[$mv]:-0}; [ "$mhz" -gt "$cur" ] && ANCHOR_MAX[$mv]=$mhz
    elif [ "$verdict" = "FAIL" ]; then ANCHOR_DONE[$mv]=1; fi
  done < <(awk -F'\t' '$2=="FINISHED"{print $1"|"$3}' "$STATE")
  # A rung that STARTED and never FINISHED ended one of two ways, and they demand
  # OPPOSITE actions: a hard lock must NOT be retried (it would crash again), while an
  # interrupt is simply unproven and should be. A reboot after the rung started is
  # SUGGESTIVE but proves nothing — the operator may have rebooted for a kernel update,
  # lost power, or just chosen to. So the evidence is shown and the OPERATOR decides.
  HUNG=$(awk -F'\t' '$2=="STARTED"{s=$1; t=$4} $2=="FINISHED"{if($1==s){s="";t=""}} END{print s"|"t}' "$STATE")
  HUNG_LABEL=${HUNG%%|*}; HUNG_TS=${HUNG##*|}
  if [ -n "$HUNG_LABEL" ]; then
    mv=${HUNG_LABEL%%mV/*}
    BOOT=$(date -d "$(uptime -s)" +%s 2>/dev/null || echo 0)
    RUNG_T=$(date -d "$HUNG_TS" +%s 2>/dev/null || echo 0)
    echo
    echo "❓ ${HUNG_LABEL} started but never finished. Evidence:"
    echo "     started:        $HUNG_TS"
    if [ "$BOOT" -gt "$RUNG_T" ] && [ "$RUNG_T" -gt 0 ]; then
      echo "     system booted:  $(uptime -s)  — $(( (BOOT-RUNG_T)/60 )) min AFTER it started"
      echo "                     (consistent with a hard lock, but a reboot has other causes)"
    else
      echo "     system booted:  $(uptime -s)  — BEFORE it started, so no reboot since"
      echo "                     (so this was an interrupt, not a machine crash)"
    fi
    XIDN=$(journalctl -k -b -1 --since "$HUNG_TS" 2>/dev/null | grep -ci xid || true)
    echo "     Xid in previous boot after that time: ${XIDN:-0}"
    echo
    if [ -t 0 ] || [ -e /dev/tty ]; then
      echo "  Did this rung CRASH the machine?"
      echo "    [y] yes — record it as a FAILURE and do not retry (safe default)"
      echo "    [n] no  — it was interrupted; retest it as unproven"
      printf '  choice [y/n]: '
      read -r hc < /dev/tty 2>/dev/null || hc=y
    else
      hc=y
      echo "  (no terminal — defaulting to 'crashed'. Retrying a crashing rung unattended"
      echo "   would loop; a wrongly skipped rung merely goes untested.)"
    fi
    case "${hc:-y}" in
      n|N) echo "  → treating ${HUNG_LABEL} as unproven; it will be re-run."
           [ "$HUNG_LABEL" != "stock" ] && unset 'ANCHOR_DONE[$mv]' ;;
      *)   echo "  → recording ${HUNG_LABEL} as a FAILURE; moving on."
           printf '%s\tFINISHED\tFAIL\t%s\t\n' "$HUNG_LABEL" "$(date -Is)" >> "$STATE"; sync
           [ "$HUNG_LABEL" != "stock" ] && ANCHOR_DONE[$mv]=1 ;;
    esac
  fi

  # INTERRUPTED rungs are unproven too — clear any bound they wrongly implied.
  while IFS= read -r l; do
    [ -n "$l" ] || continue
    m=${l%%mV/*}; [ "$l" != "stock" ] && unset "ANCHOR_DONE[$m]"
  done < <(awk -F'\t' '$3=="INTERRUPTED"{print $1}' "$STATE")
  echo "  baseline=$( [ "$BASE_DONE" = 1 ] && echo done || echo pending)  bounded anchors: ${!ANCHOR_DONE[*]:-none}"
fi

cleanup() { [ -x "$NVCURVE" ] && "$NVCURVE" write --reset >/dev/null 2>&1; echo "curve reset to stock."; }
trap cleanup EXIT INT TERM

# NOTE: the state file is truncated ONLY in the non-resume branch above. An
# unconditional `: > "$STATE"` here would erase the very history --resume just read.
say "=== two-axis undervolt exploration (unattended) ==="
say "anchors: $ANCHORS mV      clocks: $CLOCKS MHz"
say "floor:   $FLOOR MHz — an anchor that cannot hold this ends the sweep"
say "soak:    $PASSES passes per screening rung (~$(( PASSES * 167 / 60 )) min)"
say "         $CONFIRM passes to CONFIRM the winner at the end (~$(( CONFIRM * 167 / 60 )) min)"
say "state:   $STATE   (synced before every attempt — resume with --resume)"
say ""
say "Not a grid: lower voltage cannot hold MORE clock, so each lower anchor starts from"
say "the previous anchor's maximum and walks DOWN to the first rung that passes."
say ""

# Base frequency at an anchor voltage, from the card's own curve. The delta the silicon
# is being asked for is (target - base), and that ask — not the absolute clock — is what
# plausibly governs stability. Used to PREDICT where to start each lower anchor.
base_at() {
  "$NVCURVE" read --json 2>/dev/null | python3 -c '
import json,sys
d=json.load(sys.stdin); mv=float(sys.argv[1])
c=[p for p in d["vf_curve"] if p.get("domain")=="gpu" and p["volt_uV"]/1000.0>=mv]
print(int(min(c,key=lambda p:p["volt_uV"])["freq_kHz"]/1000) if c else 0)' "$1"
}

# Nearest clock in CLOCK_LIST at or below a predicted value.
snap_to() {
  echo "$CLOCK_LIST" | tr ' ' '\n' | sort -rn | awk -v t="$1" '$1<=t{print; exit}'
}

# Should the climb continue? Answers from the SCORE, which degrades before a hang.
# Returns 1 (stop) on a plateau, a regression, or widening spread. This is what lets the
# sweep stop at the practical maximum instead of walking into a crash to find it.
worth_continuing() {   # $1 = this rung, $2 = previous rung (may be empty)
  local cur prev sp base_sp
  cur=$(score_of "$1")
  [ "${cur:-0}" -gt 0 ] || return 0                    # no score to judge on — carry on
  sp=$(spread_of "$1"); base_sp=$(spread_of stock)

  # widening spread = the card is recovering from faults it has not yet crashed on
  # Floor the baseline at 2 per mille so a very tight control does not make the
  # threshold impossibly strict; 3x that is the trip point.
  [ "${base_sp:-0}" -lt 2 ] && base_sp=2
  if [ "${sp:-0}" -gt $(( base_sp * 3 )) ]; then
    say "    ! score spread ${sp}/1000 vs baseline ${base_sp}/1000 — erratic, stopping before it hangs"
    return 1
  fi
  # a regression below the baseline is degradation, not headroom
  if [ "${STOCK_SCORE:-0}" -gt 0 ] && [ "$cur" -lt $(( STOCK_SCORE * 99 / 100 )) ]; then
    say "    ! score ${cur} is below stock ${STOCK_SCORE} — degrading, stopping"
    return 1
  fi
  [ -n "$2" ] || return 0
  prev=$(score_of "$2")
  [ "${prev:-0}" -gt 0 ] || return 0
  # CLOCK STRETCHING — the rung reports a HIGHER clock while delivering LESS work.
  #
  # When the requested clock exceeds what the anchor voltage can sustain, the GPU stretches
  # the clock domain internally. nvidia-smi keeps reporting the value that was ASKED FOR,
  # so the rung looks like a win in every field except the only one that measures work.
  # It does not crash, produces no Xid and no artifact — so a stability soak calls it a
  # PASS. Measured 2026-08-04 at 1000mV/3100: clock +2.8%, power -1.8%, score -3.1%.
  #
  # The corroborating signal is POWER, and it is what makes this distinguishable from
  # ordinary run-to-run noise: power goes as f*V^2, so at a fixed voltage ceiling a real
  # clock increase MUST cost power. Clock up + power down + score down is a combination
  # a genuinely faster rung cannot produce. Requiring all three keeps this off legitimate
  # results — a rung that is merely a bit slower does not also draw less power.
  cclk=$(clock_of "$1"); pclk=$(clock_of "$2")
  cpw=$(power_of "$1");  ppw=$(power_of "$2")
  if [ "$cur" -lt $(( prev * 99 / 100 )) ] \
     && [ "${cclk:-0}" -gt "${pclk:-0}" ] && [ "${ppw:-0}" -gt 0 ] && [ "${cpw:-0}" -lt "$ppw" ]; then
    say "    ! CLOCK STRETCHING at $1 — it is stable and SLOWER than $2:"
    say "        reported clock  ${pclk} -> ${cclk} MHz   (UP)"
    say "        power           ${ppw} -> ${cpw} W       (DOWN — a real clock rise costs power)"
    say "        score           ${prev} -> ${cur}        (DOWN)"
    say "      The card is reporting a clock it is not delivering. This rung PASSES a"
    say "      stability soak and is still the wrong setting. Stopping: the useful"
    say "      ceiling is below here, and it is set by score, not by where it crashes."
    printf '%s\tNOTE\tSTRETCHED\t%s\t\n' "$1" "$(date -Is)" >> "$STATE"; sync
    return 1
  fi
  # plateau: asking for more clock is not producing more work, so the next rung risks a
  # crash for nothing. 1% is ~3x the measured 0.3% run-to-run variance.
  if [ "$cur" -lt $(( prev * 101 / 100 )) ]; then
    say "    ! score ${cur} vs ${prev} — under 1% gain, the plateau. Stopping here rather"
    say "      than climbing into a crash for no measurable benefit."
    return 1
  fi
  return 0
}

# FurMark probe — the POWER-CAPPED regime, which GravityMark never reaches.
# GravityMark runs at ~371 W of 575 W, so lowering voltage costs clock there. FurMark
# pins the cap and is forced to clock DOWN, so lowering voltage lets it clock UP within
# the same budget. That is the regime where the forum user's +7.2% came from, and the
# only way to see it on this card. Measured at baseline AND at the confirmed setting, in
# the same session, so the pair is comparable.
furmark_probe() {   # $1 = label for the log
  command -v furmark >/dev/null || { say "  (furmark not installed — skipping the capped-regime probe)"; return; }
  # PER-RUN FILENAME. This was "${STATE%.tsv}.furmark-$1.txt" — one fixed name per label,
  # so every probe overwrote the last and only the final one survived. Four stock probes
  # were taken on 2026-08-04 and three were unrecoverable except as one-line log summaries;
  # the temperature ramp that would have explained a low outlier was simply gone. A probe
  # that decides nothing still has to be re-readable, or it cannot settle a later question.
  local f="${STATE%.tsv}.furmark-$1-$(date +%H%M%S).txt"
  ( for i in $(seq 1 40); do
      nvidia-smi --query-gpu=clocks.sm,power.draw,temperature.gpu --format=csv,noheader,nounits \
        | tr -d ' ' | tr ',' ' '; sleep 3
    done > "$f" ) &
  local sp=$!
  # KEEP THE OUTPUT. It was going to /dev/null, which is why a real FPS discrepancy
  # between two probes could not be explained afterwards: FurMark prints the resolution it
  # ACTUALLY rendered, the frame count and min/avg/max FPS, and every one of those was
  # being deleted. A probe that discards the only number capable of settling a later
  # question is not cheaper, it is useless later.
  #
  # DELIBERATELY NOT --fullscreen. Without it the window manager sizes the window and
  # FurMark renders to the WINDOW rather than to --width/--height: on this machine it
  # asks for 2560x1440 and renders 2509x1371, because a dock shrinks the window. Adding
  # --fullscreen would be tidier in the abstract and WRONG here — it changes the render
  # size, breaking comparability with every probe recorded so far. The operator confirms
  # the size has been constant across all runs (2026-08-04), so it is a fixed property of
  # this setup, not a variable. The check below is what guards it: if the rendered size
  # ever changes, the log says so instead of quietly shifting the FPS.
  local out="${f%.txt}.furmark-out.txt"
  timeout -k 10 150 furmark --demo furmark-vk --width 2560 --height 1440 \
      --max-time 120 --no-score-box >"$out" 2>&1
  kill $sp 2>/dev/null
  # Surface the rendered resolution and FPS. If the resolution is not what was asked for,
  # say so loudly — every comparison against another probe is void.
  awk -F: '/resolution/ {gsub(/ /,"",$2); res=$2}
           /FPS \(min\/avg\/max\)/ {gsub(/^ +/,"",$2); fps=$2}
           /frames/ {gsub(/ /,"",$2); fr=$2}
           END { if (res!="") printf "  FurMark rendered %s   FPS min/avg/max %s   frames %s\n", res, fps, fr
                 print res > "/dev/stderr" }' \
      "$out" 2>"${f%.txt}.res" | tee -a "${STATE%.tsv}.log"
  # Compare against the size the PREVIOUS probe rendered. The requested size is not the
  # reference — the window manager overrides it and always has here. What matters is that
  # it does not CHANGE, because FPS moves with pixel count at an identical clock.
  local seen="$STATE_DIR/.furmark-render-size"
  local now; now=$(tr -d ' \n' < "${f%.txt}.res" 2>/dev/null)
  if [ -n "$now" ]; then
    if [ -f "$seen" ] && [ "$(cat "$seen")" != "$now" ]; then
      say "  ⚠️ RENDER SIZE CHANGED: $(cat "$seen") -> ${now}. FurMark FPS is NOT comparable"
      say "     with earlier probes — fewer or more pixels at the same clock. Everything"
      say "     else (MHz, W, temp) is still comparable."
    fi
    printf '%s' "$now" > "$seen"
  fi
  # WINDOW PLACEMENT IS UNCONTROLLED, unlike gpu-soak.sh which takes --screen. FurMark
  # opens wherever the window manager puts it, on whatever monitor, possibly under a dock
  # or panel. Observed 2026-08-04: it lands on a different monitor than GravityMark, with
  # a dock overlapping it. That is tolerable ONLY because this probe decides nothing — it
  # quantifies the power-capped regime for information. Its MHz/W are comparable to other
  # FurMark probes taken the same way, and to nothing else. Never against a GravityMark
  # number, and never as a benchmark score.
  awk '$2+0>300 {n++; c+=$1; w+=$2; if($3+0>t)t=$3+0}
       END{ if(n) printf "  FurMark (power-capped): %.0f MHz  %.0f W  peak %.0f C\n", c/n, w/n, t
            else print "  FurMark: no loaded samples" }' "$f" | tee -a "${STATE%.tsv}.log"
  say "    (informational only — window placement is not controlled, so this is"
  say "     comparable to other FurMark probes and to nothing else)"
}

run_rung() {   # $1 = label
  printf '%s\tSTARTED\t\t%s\n' "$1" "$(date -Is)" >> "$STATE"; sync
  local out rc
  # Capture the soak's own output directory rather than matching it by timestamp later.
  # Timestamp matching is guesswork that breaks whenever two runs land in the same second.
  out=$("$SOAK" --passes "$PASSES" --screen "$SCREEN" $WINDOWED 2>&1 | tee -a "${STATE%.tsv}.soaks.log" | awk '/^output:/{print $2}')
  rc=${PIPESTATUS[0]}
  # 130/143 mean the soak was killed by SIGINT/SIGTERM — the operator interrupted it.
  # That is UNPROVEN, not failed; recording it as FAIL would bound the anchor on no
  # evidence and permanently hide a clock that was never actually tested.
  case "$rc" in
    0)       printf '%s\tFINISHED\tPASS\t%s\t%s\n' "$1" "$(date -Is)" "$out" >> "$STATE" ;;
    2)       printf '%s\tFINISHED\tINCONCLUSIVE\t%s\t%s\n' "$1" "$(date -Is)" "$out" >> "$STATE" ;;
    130|143) printf '%s\tFINISHED\tINTERRUPTED\t%s\t%s\n' "$1" "$(date -Is)" "$out" >> "$STATE" ;;
    *)       printf '%s\tFINISHED\tFAIL\t%s\t%s\n' "$1" "$(date -Is)" "$out" >> "$STATE" ;;
  esac
  sync; return $rc
}

# Mean score and spread for a recorded rung. Instability announces itself in the SCORE
# before it crashes: a card recovering from micro-faults loses throughput and gets
# erratic. Reading that is how the sweep can find the practical maximum without ever
# having to reach the wall.
score_of() {
  local d; d=$(awk -F'\t' -v l="$1" '$1==l && $2=="FINISHED"{print $5}' "$STATE" | tail -1)
  [ -n "$d" ] && [ -s "$d/scores.txt" ] || { echo 0; return; }
  awk '{s+=$1;n++} END{printf "%d", (n? s/n : 0)}' "$d/scores.txt"
}
# Peak-to-peak spread in PER MILLE, not percent. The baseline's real spread is ~2 per
# mille (0.19%), which truncates to 0 in integer percent — silently disabling the guard
# that depends on it. Integer percent has no resolution at the scale being measured.
spread_of() {   # returns tenths of a percent
  local d; d=$(awk -F'\t' -v l="$1" '$1==l && $2=="FINISHED"{print $5}' "$STATE" | tail -1)
  [ -n "$d" ] && [ -s "$d/scores.txt" ] || { echo 0; return; }
  awk '{s+=$1; if(!mn||$1<mn)mn=$1; if($1>mx)mx=$1}
       END{ if(NR>1) printf "%d", (mx-mn)*1000/(s/NR); else print 0 }' "$d/scores.txt"
}

# Mean delivered clock for a recorded rung, from the soak dir the state file names.
clock_of() {
  local d
  d=$(awk -F'\t' -v l="$1" '$1==l && $2=="FINISHED"{print $5}' "$STATE" | tail -1)
  [ -n "$d" ] && [ -f "$d/sensors.txt" ] || { echo 0; return; }
  awk '$3!="n/a" && $3+0>100 {n++; f+=$2} END{printf "%d", (n? f/n : 0)}' "$d/sensors.txt"
}
power_of() {
  local d
  d=$(awk -F'\t' -v l="$1" '$1==l && $2=="FINISHED"{print $5}' "$STATE" | tail -1)
  [ -n "$d" ] && [ -f "$d/sensors.txt" ] || { echo 0; return; }
  awk '$3!="n/a" && $3+0>100 {n++; p+=$3} END{printf "%d", (n? p/n : 0)}' "$d/sensors.txt"
}

# ── baseline ────────────────────────────────────────────────────────────────────────
if [ "$BASE_DONE" = 1 ]; then
  say "BASELINE — already recorded in a previous run, skipping."
else
  say "───────────────────────────────────────────────"
  say "BASELINE — stock   ($(date +%H:%M:%S))"
  "$NVCURVE" write --reset >/dev/null 2>&1
  run_rung "stock" || { say "baseline FAILED — unstable at stock. Stop and investigate."; exit 1; }
  say "  ✓ baseline recorded"
fi
STOCK_CLK=$(clock_of stock); STOCK_SCORE=$(score_of stock)
if [ "${STOCK_CLK:-0}" -gt 0 ]; then
  say "  stock delivers ${STOCK_CLK} MHz, score ${STOCK_SCORE}, spread $(spread_of stock)/1000"
  say "  — the crossover and plateau rules are measured against these"
  say "  probing the power-capped regime at stock:"
  furmark_probe stock
else
  say "  ⚠️ could not read the stock clock; the crossover stop rule is DISABLED"
fi

CLOCK_LIST=$(echo "$CLOCKS" | tr ' ' '\n' | sort -n | tr '\n' ' ')
CEILING=""          # highest clock known to pass at the previous (higher) anchor
MAX_DELTA=0         # largest (target - base) that has passed anywhere — the predictor

# ON RESUME, REBUILD THE PREDICTOR FROM THE STATE FILE.
#
# These two are learned by WALKING anchors, so a resume that does not re-walk the earlier
# anchors starts with both empty — and empty CEILING selects the FIRST-ANCHOR branch
# below, which climbs from the bottom of the clock list until something FAILS. That is the
# branch that finds a limit by crashing into it. It is the correct behaviour for a genuine
# first anchor and the wrong behaviour here, where higher anchors already established what
# the silicon holds.
#
# Concretely, resuming `--anchors "900 875"` after 1000 and 950 mV completed: without this,
# 900 mV would restart at the lowest clock and climb rung by rung — ~11 min each — into a
# region a hard lock has already been seen in. With it, 900 mV starts at its own base plus
# the largest delta that has actually passed, which is the whole reason the two-axis walk
# is cheaper than a grid.
if [ "$RESUME" = 1 ] && [ "${#ANCHOR_MAX[@]}" -gt 0 ]; then
  for a in $(printf '%s\n' "${!ANCHOR_MAX[@]}" | sort -rn); do
    m=${ANCHOR_MAX[$a]}
    [ -z "$CEILING" ] && CEILING=$m        # highest completed anchor bounds the lower ones
    b=$(base_at "$a")
    if [ "${b:-0}" -gt 0 ]; then
      d=$(( m - b ))
      [ "$d" -gt "$MAX_DELTA" ] && MAX_DELTA=$d
    fi
  done
  if [ -n "$CEILING" ]; then
    say "restored from the previous run: ceiling ${CEILING} MHz, best proven delta +${MAX_DELTA} MHz"
    say "  (without these a resume would restart the climb from the bottom and find each"
    say "   anchor's limit by crashing into it)"
  fi
fi

for mv in $ANCHORS; do
  say ""
  say "───────────────────────────────────────────────"
  say "ANCHOR ${mv} mV   ($(date +%H:%M:%S))"
  BEST_AT_ANCHOR="${ANCHOR_MAX[$mv]:-}"
  if [ -n "${ANCHOR_DONE[$mv]:-}" ] && [ -n "$BEST_AT_ANCHOR" ]; then
    say "  already determined in a previous run: maximum ${BEST_AT_ANCHOR} MHz — skipping"
    CEILING=$BEST_AT_ANCHOR
    continue
  fi

  PREV_LABEL=""
  if [ -z "$CEILING" ]; then
    # first anchor: climb until the score stops improving, or until failure
    for mhz in $CLOCK_LIST; do
      if grep -qF "${mv}mV/${mhz}	FINISHED" "$STATE" 2>/dev/null; then
        say "  ${mhz} MHz — already decided in a previous run, skipping"; continue; fi
      say "  trying ${mhz} MHz ..."
      "$FLATTEN" --mv "$mv" --mhz "$mhz" >/dev/null 2>&1 || { say "    flatten refused — skipping"; continue; }
      if run_rung "${mv}mV/${mhz}"; then
        say "    ✓ passed"
        if ! worth_continuing "${mv}mV/${mhz}" "$PREV_LABEL"; then
          BEST_AT_ANCHOR=$mhz; "$NVCURVE" write --reset >/dev/null 2>&1; break
        fi
        BEST_AT_ANCHOR=$mhz; PREV_LABEL="${mv}mV/${mhz}"
      else say "    ✗ failed — anchor maximum is ${BEST_AT_ANCHOR:-none}"; break; fi
      "$NVCURVE" write --reset >/dev/null 2>&1
    done
  else
    # Lower anchor. Start from the DELTA that worked highest so far rather than from the
    # previous anchor's absolute clock — at a lower anchor the same clock is a much
    # bigger ask, so the naive start is usually several doomed rungs above the answer.
    BASE=$(base_at "$mv")

    # ── DELTA CEILING: never ask for more than one step beyond what has been PROVEN ────
    #
    # This guard exists because its absence hard-locked the machine on 2026-08-04.
    # At 900 mV: base 2002, best proven delta +435, so the prediction was 2437 MHz — BELOW
    # the whole clock list (floor 2700). snap_to correctly returned EMPTY, and the old
    # fallback `START=${PRED:-$CEILING}` then reached for the CEILING, 3100 MHz: a delta of
    # +1098 where +435 was the most ever proven. The flatten refused that one (its own
    # ±1000 cap), which was reported as a rung "failure", so the descend path tried 3000 —
    # delta +998, just under the cap, applied, and the machine died.
    #
    # The prediction being below the list is not a missing answer, it is an ANSWER: this
    # anchor cannot reach the floor clock. Falling back to the most aggressive rung when
    # the evidence says "too low" is backwards, and it is how a sweep finds a limit by
    # crashing rather than by predicting.
    STEP=$(echo "$CLOCK_LIST" | tr ' ' '\n' | sort -n | awk 'NR>1{d=$1-p; if(!m||d<m)m=d} {p=$1} END{print (m?m:100)}')
    DELTA_CAP=0
    if [ "${BASE:-0}" -gt 0 ] && [ "${MAX_DELTA:-0}" -gt 0 ]; then
      DELTA_CAP=$(( BASE + MAX_DELTA + STEP ))
      PRED=$(snap_to $(( BASE + MAX_DELTA )))
      say "  predicted start ${PRED:-none} MHz  (base ${BASE} + best delta ${MAX_DELTA})"
      say "  hard cap ${DELTA_CAP} MHz  (one ${STEP} MHz step past the proven delta)"
      if [ "$DELTA_CAP" -lt "$FLOOR" ]; then
        say "  ${mv} mV cannot reach the floor ${FLOOR} MHz without asking more than the"
        say "  silicon has ever proven (+${MAX_DELTA}). That is this anchor's answer — it is"
        say "  too low. Ending the sweep rather than crashing to confirm it."
        break
      fi
    fi

    # Prefer the prediction; fall back to the CEILING only when it is not already past the
    # cap. Never start above the cap.
    START=${PRED:-$CEILING}
    if [ "$DELTA_CAP" -gt 0 ] && [ "$START" -gt "$DELTA_CAP" ]; then
      START=$(snap_to "$DELTA_CAP")
      [ -n "$START" ] || { say "  no clock in the list is within the proven delta — skipping ${mv} mV"; continue; }
      say "  start reduced to ${START} MHz by the proven-delta cap"
    fi

    # Try the prediction, then move in whichever direction the result points. Climbing
    # after a pass is the safeguard: if delta does NOT govern, the prediction starts too
    # low and a one-way descent would silently under-report this anchor's maximum.
    if grep -qF "${mv}mV/${START}	FINISHED" "$STATE" 2>/dev/null; then
      say "  ${START} MHz already decided — skipping"
    else
      say "  trying ${START} MHz (prediction) ..."
      if "$FLATTEN" --mv "$mv" --mhz "$START" >/dev/null 2>&1 && run_rung "${mv}mV/${START}"; then
        say "    ✓ passed"; BEST_AT_ANCHOR=$START
      else
        say "    ✗ failed"
      fi
      "$NVCURVE" write --reset >/dev/null 2>&1
    fi

    if [ -n "$BEST_AT_ANCHOR" ]; then
      # passed the prediction — climb to make sure we are not leaving clock on the table
      for mhz in $(echo "$CLOCK_LIST" | tr ' ' '\n' | sort -n | awk -v s="$START" '$1>s'); do
        grep -qF "${mv}mV/${mhz}	FINISHED" "$STATE" 2>/dev/null && continue
        if [ "$DELTA_CAP" -gt 0 ] && [ "$mhz" -gt "$DELTA_CAP" ]; then
          say "  stopping the climb at ${mhz} MHz — past the proven-delta cap ${DELTA_CAP}"; break; fi
        say "  climbing to ${mhz} MHz ..."
        "$FLATTEN" --mv "$mv" --mhz "$mhz" >/dev/null 2>&1 || { say "    flatten refused (delta out of range) — NOT a rung failure"; continue; }
        if run_rung "${mv}mV/${mhz}"; then say "    ✓ passed"; BEST_AT_ANCHOR=$mhz
        else say "    ✗ failed — anchor maximum ${BEST_AT_ANCHOR}"; break; fi
        "$NVCURVE" write --reset >/dev/null 2>&1
      done
    else
      # failed the prediction — descend to the first pass
      for mhz in $(echo "$CLOCK_LIST" | tr ' ' '\n' | sort -rn | awk -v s="$START" '$1<s'); do
        grep -qF "${mv}mV/${mhz}	FINISHED" "$STATE" 2>/dev/null && continue
        # The descend path is where the 2026-08-04 hard lock happened: START had been
        # wrongly set to the CEILING, its flatten was refused as out-of-range, and the
        # descent then found the first clock the ±1000 cap would ACCEPT — +998 MHz, more
        # than twice anything proven. "The flatten accepted it" is not evidence of safety.
        if [ "$DELTA_CAP" -gt 0 ] && [ "$mhz" -gt "$DELTA_CAP" ]; then
          say "  skipping ${mhz} MHz — past the proven-delta cap ${DELTA_CAP}"; continue; fi
        say "  descending to ${mhz} MHz ..."
        "$FLATTEN" --mv "$mv" --mhz "$mhz" >/dev/null 2>&1 || { say "    flatten refused (delta out of range) — NOT a rung failure"; continue; }
        if run_rung "${mv}mV/${mhz}"; then say "    ✓ passed — anchor maximum ${mhz}"; BEST_AT_ANCHOR=$mhz; break
        else say "    ✗ failed — stepping down"; fi
        "$NVCURVE" write --reset >/dev/null 2>&1
      done
    fi
    unset PRED
  fi

  "$NVCURVE" write --reset >/dev/null 2>&1
  if [ -z "$BEST_AT_ANCHOR" ] || [ "$BEST_AT_ANCHOR" -lt "$FLOOR" ]; then
    say "  ${mv} mV holds nothing at or above ${FLOOR} MHz (best: ${BEST_AT_ANCHOR:-none}) — too low."
    say "  Ending the sweep; lower anchors can only be worse."
    break
  fi
  # ── STOP RULE, grounded in the goal rather than a threshold ───────────────────────
  # Above the stock baseline clock, a lower anchor is FREE power — strictly better, keep
  # going. Below it you have started trading performance for watts, which is not the
  # stated goal. The crossover is the decision point, and the 1% tolerance is the
  # measured run-to-run variance (0.3% spread), not a guess.
  DELIVERED=$(clock_of "${mv}mV/${BEST_AT_ANCHOR}")
  if [ "${STOCK_CLK:-0}" -gt 0 ] && [ "$DELIVERED" -gt 0 ]; then
    THRESH=$(( STOCK_CLK * 99 / 100 ))
    say "  delivered ${DELIVERED} MHz vs stock ${STOCK_CLK} MHz (floor ${THRESH})"
    if [ "$DELIVERED" -lt "$THRESH" ]; then
      say ""
      say "  ► STOPPING: ${mv} mV delivers ${DELIVERED} MHz, below the stock baseline."
      say "    Lower anchors can only be slower. Past this point every further step"
      say "    trades performance for watts, which is not the goal — so the sweep ends"
      say "    here rather than spending hours mapping trades you would not take."
      CEILING=$BEST_AT_ANCHOR
      break
    fi
  fi

  CEILING=$BEST_AT_ANCHOR
  B=$(base_at "$mv")
  if [ "${B:-0}" -gt 0 ]; then
    D=$(( BEST_AT_ANCHOR - B ))
    [ "$D" -gt "${MAX_DELTA:-0}" ] && MAX_DELTA=$D
    say "  → ${mv} mV maximum: ${BEST_AT_ANCHOR} MHz  (delta +${D} over its base ${B})"
  else
    say "  → ${mv} mV maximum: ${BEST_AT_ANCHOR} MHz"
  fi
done

# ── confirm the winner with a long soak ─────────────────────────────────────────────
# Screening rungs are deliberately short — instability at the edge is probabilistic, so
# a short pass is a SCREEN, not proof. The pair that survives screening earns one long
# soak before it is recommended.
# Pick the winner by MEASURED SCORE, not by target clock.
#
# WHY NOT CLOCK. A rung that passes is not thereby faster. Measured 2026-08-04:
# 1000mV/3100 passed 4 clean passes (0 Xid) and scored 79 778 against 1000mV/3000's
# 82 329 — 3.1% SLOWER while REPORTING a 2.8% higher clock, at 1.8% LESS power. Power
# tracks f·V²; with the voltage ceiling unchanged a real clock rise must cost power. It
# did not, so the effective clock was below the reported one: the GPU stretches the clock
# internally when the requested value exceeds what the voltage sustains, and nvidia-smi
# keeps echoing what was asked for. Selecting on target clock picks exactly that rung.
# Score is the only field that measures delivered work, so score decides. Ties go to the
# LOWER anchor — same speed for less voltage; at equal anchor the HIGHER clock, which
# costs nothing in the coasting regime and clocks up inside the cap in the capped one.
#
# MARGIN IS APPLIED BEFORE THE CHOICE, NOT AFTER. Ranking first and backing off the
# winner afterwards compares candidates that have not had the same rule applied, and the
# back-off can demote the winner below a rival it had just beaten. On the 2026-08-04 data
# that is not hypothetical: score-ranking picks 950mV/3000 (82 400), whose anchor ceiling
# IS 3000 — 950mV/3100 hard-locked the machine — so it backs off to an untested
# 950mV/2900, while 1000mV/3000 (82 329, a 0.1% difference against 2.4% run-to-run
# spread) needs no back-off at all because 1000mV/3100 passed above it. Deciding on the
# post-margin setting picks 1000mV/3000, which is the right answer.
#
#   stability ceiling(anchor) = highest clock that PASSED at that anchor
#   a rung is COVERED when its clock is below its anchor's ceiling — a higher rung
#   already passed, so the margin is demonstrated rather than assumed
#
# Covered rungs are preferred outright: their score is measured AND their margin is
# proven. Only if nothing is covered does the old back-off-from-the-top rule apply, and
# then the setting confirmed is one rung down from the best — untested by definition,
# which is exactly why it is the fallback and not the default.
RUNGS=$(while IFS= read -r r; do
          [ -n "$r" ] || continue
          printf '%s\t%s\t%s\n' "$(score_of "$r")" "${r%%mV/*}" "${r##*/}"
        done < <(awk -F'\t' '$2=="FINISHED" && $3=="PASS" && $1!="stock" && $1 !~ /confirm/ {print $1}' "$STATE" | sort -u) \
        | awk -F'\t' '$1>0')
CEILS=$(awk -F'\t' '$2=="FINISHED" && $3=="PASS" && $1!="stock" && $1 !~ /confirm/ {
          split($1,p,"mV/"); if(p[2]+0>m[p[1]]) m[p[1]]=p[2]+0 } END{for(a in m) print a"\t"m[a]}' "$STATE")

COVERED=$(echo "$RUNGS" | awk -F'\t' -v C="$CEILS" '
  BEGIN{ n=split(C,L,"\n"); for(i=1;i<=n;i++){ split(L[i],f,"\t"); ceil[f[1]]=f[2]+0 } }
  $3+0 < ceil[$2] { print }' | sort -k1,1nr -k2,2n -k3,3nr | head -1)
BEST=$(echo "$RUNGS" | sort -k1,1nr -k2,2n -k3,3nr | head -1)

if [ -n "$COVERED" ]; then WIN_ROW=$COVERED; COVERED_WIN=1; else WIN_ROW=$BEST; COVERED_WIN=""; fi
WIN=$(echo "$WIN_ROW" | awk -F'\t' '{print $2"mV/"$3}')

if [ -n "$WIN" ]; then
  wmv=${WIN%%mV/*}; wmax=${WIN##*/}
  CEIL_AT=$(echo "$CEILS" | awk -F'\t' -v a="$wmv" '$1==a{print $2+0}')
  say ""
  say "───────────────────────────────────────────────"
  if [ -n "$COVERED_WIN" ]; then
    wmhz=$wmax
    say "Best setting by MEASURED SCORE, margin included: ${wmv} mV / ${wmax} MHz  ($(score_of "$WIN") points)"
    say "Its anchor's stability ceiling is ${CEIL_AT} MHz — a HIGHER rung already passed,"
    say "so ${wmax} MHz has demonstrated margin above it. Confirming it as-is; backing off"
    say "further would discard the win for margin that is already proven."
    bs=$(echo "$BEST" | cut -f1)
    if [ "$bs" -gt "$(score_of "$WIN")" ]; then
      say "  (a higher raw score exists — $(echo "$BEST" | awk -F'\t' '{print $2"mV/"$3}') at ${bs} — but nothing above it is"
      say "   proven stable, so it would have to back off to an untested rung.)"
    fi
  else
    say "Best passing pair by SCORE: ${wmv} mV / ${wmax} MHz  ($(score_of "$WIN") points)"
    wmhz=$(echo "$CLOCK_LIST" | tr ' ' '\n' | sort -n | awk -v m="$wmax" '$1<m{p=$1} END{print p+0}')
    [ "${wmhz:-0}" -gt 0 ] || wmhz=$wmax   # nothing below it — confirm the max itself
    if [ "$wmhz" != "$wmax" ]; then
      say "NO rung anywhere has a proven-stable rung above it, so nothing carries measured"
      say "margin. Falling back to the back-off rule: confirming ${wmv} mV / ${wmhz} MHz,"
      say "one rung below the best. Margin covers a warm day, a driver update, and aging;"
      say "instability at the edge is probabilistic."
    else
      say "No rung below it in the tested set — confirming the maximum itself."
    fi
  fi
  if [ "$CONFIRM" -gt "$PASSES" ]; then
    say "CONFIRMING ${wmv} mV / ${wmhz} MHz with $CONFIRM passes   ($(date +%H:%M:%S))"
    if "$FLATTEN" --mv "$wmv" --mhz "$wmhz" >/dev/null 2>&1; then
      PASSES=$CONFIRM
      if run_rung "${wmv}mV/${wmhz}-confirm"; then
        CONFIRMED=1
        say "  ✓ CONFIRMED over $CONFIRM passes — this is the setting to keep."
        say ""
        say "  probing the power-capped regime at this setting (compare with stock above):"
        "$FLATTEN" --mv "$wmv" --mhz "$wmhz" >/dev/null 2>&1
        furmark_probe confirmed
        say "  ^ THIS is where the gain shows as more CLOCK at the same 575 W, rather"
        say "    than as less power. Both come from the same setting."
        say "     sudo $FLATTEN --mv $wmv --mhz $wmhz"
        say "     sudo $NVCURVE profile save quiet"
      else
        say "  ✗ FAILED the long soak. Screening was not enough evidence — drop another rung."
      fi
    fi
    "$NVCURVE" write --reset >/dev/null 2>&1
  fi
fi

say ""
say "═══════════════════════════════════════════════"
say "SWEEP COMPLETE — $(date +%H:%M:%S)"
say ""
"$HERE/gpu-ladder-report.sh" --state "$STATE" 2>&1 | tee -a "${STATE%.tsv}.log"
say ""
# Do not claim a confirmation that did not happen. The 2026-08-04 run printed "already
# been applied and soaked" over a confirm rung recorded INTERRUPTED 25 s in — a completion
# claim contradicted by the very state file printed two lines above it.
if [ "${CONFIRMED:-0}" = 1 ]; then
  say "The pair above passed the long soak. That is the setting to keep — no further"
  say "adjustment is needed."
elif [ -n "${WIN:-}" ]; then
  say "⚠️ The winner above was chosen from SCREENING runs only — the long confirmation"
  say "   soak did not complete. Screening is 4 passes; instability at the edge is"
  say "   probabilistic. Confirm before trusting it daily:"
  say "     sudo $FLATTEN --mv ${wmv:-?} --mhz ${wmhz:-?}"
  say "     sudo $SOAK --screen $SCREEN --passes $CONFIRM"
fi
say ""
printf 'SWEEP\tCOMPLETE\t\t%s\n' "$(date -Is)" >> "$STATE"; sync
say "Curve reset to stock. Nothing persists across a reboot."
say "This run: $STATE"
