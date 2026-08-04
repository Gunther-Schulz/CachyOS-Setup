#!/usr/bin/env bash
# gpu-ladder-report.sh — join a ladder's state file with its per-rung soak data and
# print ONE comparison table: power, clock, temperature, fan and score per rung.
#
# WHY THIS IS SEPARATE. The ladders record only PASS/FAIL; each rung's measurements live
# in its own ~/bench/soak-*/ directory, written by gpu-soak.sh. Without joining them you
# are scrolling terminal history to compare rungs — and the whole point of walking the
# anchor down is to SEE where the returns flatten, which is a table question.
#
# It reads only completed files, so it is safe to run WHILE a ladder is in progress —
# useful for deciding to stop early once the gains die, which is a better stopping rule
# than running until something hangs.
#
# Rungs are matched to soak directories by TIMESTAMP: each STARTED line in the state file
# is paired with the first soak directory created at or after it.
#
# Usage:
#   ./tools/gpu-ladder-report.sh --clock            # the CURRENT clock ladder
#   ./tools/gpu-ladder-report.sh                    # flatten ladder (superseded)
#   ./tools/gpu-ladder-report.sh --offset           # the global-offset ladder instead
#   ./tools/gpu-ladder-report.sh --state <path>

set -uo pipefail
export LC_ALL=C

home=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)
STATE="$home/bench/flatten-ladder-state.tsv"
UNIT="mV"

while [ $# -gt 0 ]; do
  case "$1" in
    --clock)  STATE="$home/bench/clock-ladder-state.tsv"; UNIT="MHz"; shift ;;
    --offset) STATE="$home/bench/uv-ladder-state.tsv"; UNIT="MHz"; shift ;;
    --state) STATE=$2; shift 2 ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

[ -f "$STATE" ] || { echo "no state file at $STATE" >&2; exit 1; }
ROWS=$(mktemp); trap 'rm -f "$ROWS"' EXIT

# Stock reference. There is deliberately NO built-in default: the previous 370 W / 2803 MHz
# came from this repo's own 5090 and would have been silently applied to anyone else's card,
# turning every "vs stock" figure into a comparison against unrelated hardware — wrong, and
# wrong in a way that reads as a measurement. A ladder measures its own stock rung; if it
# has not yet, the column says so instead of inventing a baseline.
REF_W=0; REF_MHZ=0; REF_SC=0; SESSION_REF=""

printf '%8s %8s %9s %9s %8s %7s %9s %10s %s\n' \
  "rung" "verdict" "mean W" "vs stock" "mean MHz" "peak C" "peak fan" "mean score" "passes"
printf '%8s %8s %9s %9s %8s %7s %9s %10s %s\n' \
  "--------" "--------" "---------" "---------" "--------" "-------" "---------" "----------" "------"

# Parse with awk, NOT `IFS=$'\t' read`: tab is an IFS *whitespace* character, so bash
# COLLAPSES consecutive tabs and the empty verdict field silently disappears — shifting
# the timestamp into the wrong variable and breaking every join.
while IFS='|' read -r rung ts; do
  [ -n "$rung" ] || continue
  # Prefer the soak directory the ladder RECORDED for this rung (column 5). Timestamp
  # matching is a fallback for older state files that predate it — and it is guesswork
  # that silently joins two rungs to the same directory when their windows overlap,
  # which is exactly what it did here: 1000mV/2800 and 1000mV/2900 reported identical
  # power, clock and score because both resolved to the first run's data.
  d=$(awk -F'\t' -v l="$rung" '$1==l && $2=="FINISHED" && $5!=""{print $5}' "$STATE" | tail -1)
  # Only a rung that PASSED may fall back to timestamp matching. Requiring merely
  # FINISHED was not enough: 950mV/3100 FAILED — it hard-locked the machine — had no
  # recorded directory, and the fallback handed it its neighbour's data, so the report
  # printed the rung that killed the box as "WINS BOTH  score +7.2%". A rung with no
  # data of its own must show no data, never the nearest run's.
  fin=$(awk -F'\t' -v r="$rung" '$1==r && $2=="FINISHED" && $3=="PASS"{print 1}' "$STATE" | tail -1)
  if [ -z "$d" ] && [ -n "$fin" ]; then
    d=$(for x in "$home"/bench/soak-*/; do
          [ -f "$x/sensors.txt" ] || continue
          xs=$(date -r "$x" +%s 2>/dev/null) || continue
          rs=$(date -d "$ts" +%s 2>/dev/null) || continue
          [ "$xs" -ge $((rs - 5)) ] && echo "$xs $x"
        done | sort -n | head -1 | cut -d' ' -f2-)
  fi
  # verdict comes from the matching FINISHED line, if it exists yet
  v=$(awk -F'\t' -v r="$rung" '$1==r && $2=="FINISHED"{print $3}' "$STATE" | tail -1)
  v=${v:-RUNNING}
  if [ -z "$d" ] || [ ! -s "$d/sensors.txt" ]; then
    printf '%8s %8s %9s %9s %8s %7s %9s %10s %s\n' "$rung" "$v" "-" "-" "-" "-" "-" "-" "-"
    continue
  fi
  read -r mw mf pt pfan < <(awk '$3!="n/a" && $3+0>100 {n++; w+=$3; f+=$2; if($4+0>t)t=$4+0; if($5+0>fa)fa=$5+0}
       END{if(n) printf "%.0f %.0f %.0f %.0f", w/n, f/n, t, fa; else printf "- - - -"}' "$d/sensors.txt")
  ms="-"; np=0
  if [ -s "$d/scores.txt" ]; then
    np=$(grep -c . "$d/scores.txt")
    ms=$(awk '{s+=$1;n++} END{if(n) printf "%.0f", s/n; else print "-"}' "$d/scores.txt")
  fi
  # The ladder's own stock rung IS the reference — measured on this card, in this session,
  # under these ambient conditions. There is no other source for it.
  if [ "$rung" = "stock" ] && [ "$mw" != "-" ]; then REF_W=$mw; REF_MHZ=$mf; REF_SC=$ms; SESSION_REF=1; fi
  dw="-"
  [ "$mw" != "-" ] && [ "${REF_W:-0}" -gt 0 ] \
    && dw=$(awk -v a="$mw" -v b="$REF_W" 'BEGIN{printf "%+.0f%%", (a/b-1)*100}')
  printf '%8s %8s %9s %9s %8s %7s %9s %10s %s\n' \
    "$rung" "$v" "$mw" "$dw" "$mf" "$pt" "$pfan" "$ms" "$np"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$rung" "$v" "$mw" "$mf" "$ms" "$np" >> "$ROWS"
done < <(awk -F'\t' '$2=="STARTED"{print $1"|"$4}' "$STATE")

echo
if [ "${REF_W:-0}" -gt 0 ]; then
  echo "stock reference: ${REF_MHZ} MHz, ${REF_W} W${SESSION_REF:+  <- measured in THIS ladder run (proper control)}"
else
  echo "stock reference: NONE — this ladder has no completed 'stock' rung, so the"
  echo "  'vs stock' column is blank and no verdict is computed. Run the sweep from the"
  echo "  start (it measures stock first) rather than comparing against a number from"
  echo "  another card or another day."
fi
echo

# ── the analysis, rather than instructions for doing it by hand ─────────────────────
awk -F'\t' -v rw="$REF_W" -v rf="$REF_MHZ" -v rs="$REF_SC" '
BEGIN { if (rw+0 <= 0 || rf+0 <= 0) {
          print "No stock baseline in this ladder — nothing to compare against."
          print "The verdict is deliberately withheld rather than computed against a"
          print "reference from different hardware."; exit } }
# Only PASSING rungs are ranked. A FAIL or INTERRUPTED rung has no usable measurement,
# and feeding it to the comparison produced nonsense with a confident face: the
# 2026-08-04 report scored an interrupted confirm at "-100.0%" and tagged it STRETCHED,
# and listed a hard-locking FAIL rung as WINS BOTH. Verdicts rank results; a rung that
# did not produce one is listed below, plainly, as not having produced one.
$1=="stock" || $3=="-" || $2=="RUNNING" { next }
$2!="PASS" { nb++; bad[nb]=$1 "  [" $2 "]"; next }
$5+0 <= 0 { nb++; bad[nb]=$1 "  [no score recorded]"; next }
{ n++; rung[n]=$1; verd[n]=$2; w[n]=$3+0; f[n]=$4+0; sc[n]=$5+0
  # split "1000mV/3100" into its anchor and its TARGET clock. The target is what was
  # asked for; f[] is what the card reported delivering. Keeping them apart is the whole
  # point — the gap between them is the defect this tool exists to surface.
  if (split($1, q, "mV/")==2) { anc[n]=q[1]+0; tgt[n]=q[2]+0
    if (verd[n]=="PASS" && tgt[n]>ceil[anc[n]]) ceil[anc[n]]=tgt[n] } }
END {
  if (n==0) { print "No completed rungs yet — nothing to analyse."; exit }
  if (rs+0 <= 0) { print "Stock rung has no score — cannot rank. Re-run the baseline."; exit }
  print "═══ VERDICT ═══"
  print "  Ranked by SCORE. Reported clock is NOT used: a rung can report a higher clock"
  print "  and deliver less work (the card stretches the clock when the voltage cannot"
  print "  sustain it), which is stable, passes every soak, and is still the wrong setting."
  print ""
  best=0
  for (i=1;i<=n;i++) {
    ds=(sc[i]/rs-1)*100; dw=(w[i]/rw-1)*100; df=(f[i]/rf-1)*100
    tag = (verd[i]!="PASS") ? "  [" verd[i] "]" : ""
    # STRETCHED is a within-anchor comparison, NOT a stock one. A rung can beat stock
    # comfortably and still be stretched relative to the rung below it — 1000mV/3100
    # scored +3.7% over stock while losing 3.1% to 1000mV/3000. Comparing against stock
    # would have called it a winner, which is the error this whole tag exists to prevent.
    str_by=""
    for (j=1;j<=n;j++)
      if (j!=i && anc[j]==anc[i] && tgt[j]<tgt[i] && f[j]<f[i] && sc[j]>sc[i]*1.01) str_by=rung[j]
    # COVERED: a higher rung at the same anchor passed, so this margin is measured.
    # (No apostrophes in here — the awk program is single-quoted and one would end it.)
    cov = (ceil[anc[i]] > tgt[i])
    if (str_by!="") { sb=0; for (k=1;k<=n;k++) if (rung[k]==str_by) sb=sc[k]
                      note="STRETCHED — reports more clock than " str_by " but delivers " sprintf("%+.1f", (sc[i]/sb-1)*100) "% work" }
    else if (ds>=-0.5 && dw<=-2) { note="WINS BOTH — score held, power down" (cov?"  [margin proven]":"  [top rung — no margin above]")
                                   if(verd[i]=="PASS" && cov && (best==0 || sc[i]>sc[best])) best=i }
    else if (ds>=-0.5)           { note="score held, power not improved" }
    else if (dw<=-2)             { note=sprintf("trade: %.1f%% score for %.1f%% power", -ds, -dw) }
    else                         { note="worse on both — no reason to use" }
    printf "  %-12s score %+5.1f%%   power %+5.1f%%   %s%s\n", rung[i], ds, dw, note, tag
  }
  print ""
  if (best) {
    printf "  ► BEST: %s — %+.1f%% score at %.0f%% less power.\n", rung[best], (sc[best]/rs-1)*100, -(w[best]/rw-1)*100
    printf "    A higher rung at %d mV (%d MHz) also passed, so its stability margin is\n", anc[best], ceil[anc[best]]
    print  "    measured rather than assumed. Faster-or-equal, cooler, and covered."
    # name a higher raw score that lost only because it had no proven margin
    raw=0; for (i=1;i<=n;i++) if (verd[i]=="PASS" && sc[i]>sc[best] && (raw==0 || sc[i]>sc[raw])) raw=i
    if (raw) printf "    (%s scored higher at %d, but nothing above it passed — it would have\n     to back off to an untested rung.)\n", rung[raw], sc[raw]
  } else {
    print "  ► No rung both beats stock score while cutting power AND has a passing rung"
    print "    above it. Either finish the ladder, or accept the best top-rung result and"
    print "    back it off by one — untested, which is why it is not recommended here."
  }
  if (n>=2) {
    print ""
    for (i=2;i<=n;i++) {
      gain=(sc[i]/sc[i-1]-1)*100
      if (gain < 1 && gain > -1)
        printf "  ! %s over %s is only %+.1f%% score — returns are flattening here.\n", rung[i], rung[i-1], gain
    }
  }
  if (nb) {
    print ""
    print "  Not ranked (no usable measurement):"
    for (i=1;i<=nb;i++) printf "    %s\n", bad[i]
  }
  print ""
  print "  Reminder: prefer a rung with a PASSING rung ABOVE it at the same anchor — that"
  print "  margin is demonstrated. Only back off one rung when nothing above it passed."
}' "$ROWS"
