#!/usr/bin/env bash
# gpu-hang-watch — surface NVIDIA Xid GPU faults from the kernel log, live or
# after the fact, with the Xid numbers decoded.
#
# Why this exists: a game that "freezes" gives you no error message. The GPU
# fault that actually killed it is only in the kernel ring buffer, where nobody
# looks. Xid 109 (CTX SWITCH TIMEOUT) followed seconds later by Xid 31 (MMU
# fault) is the signature of a GPU hang taking the render context down — the
# game window is still there, the GPU is not.
#
# Why journalctl and not dmesg: `dmesg` needs root here (kernel.dmesg_restrict),
# and a non-root `dmesg` exits quietly with almost no output — so a grep over it
# returns "no faults" whether or not there were any. That silent-empty read is
# the exact failure this script avoids: journalctl -k works unprivileged for
# users in systemd-journal/wheel, and --self-test proves the reader is alive
# before any absence is reported.
#
# Usage:
#   gpu-hang-watch.sh                  # summarize this boot, then follow live
#   gpu-hang-watch.sh --since "1 hour ago"
#   gpu-hang-watch.sh --boot           # this boot only, no follow
#   gpu-hang-watch.sh --self-test      # prove the log reader works, then exit

set -uo pipefail

PROG=${0##*/}
SINCE=""
FOLLOW=1
SELF_TEST=0

usage() {
	sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
	exit "${1:-0}"
}

while [ $# -gt 0 ]; do
	case "$1" in
	--since)
		SINCE=${2:?--since needs a value}
		FOLLOW=0
		shift 2
		;;
	--boot)
		FOLLOW=0
		shift
		;;
	--self-test)
		SELF_TEST=1
		shift
		;;
	-h | --help) usage 0 ;;
	*)
		printf '%s: unknown argument: %s\n' "$PROG" "$1" >&2
		usage 2
		;;
	esac
done

# Xid meanings that matter for a desktop gaming box. Anything not listed is
# printed with its raw number rather than guessed at.
xid_meaning() {
	case "$1" in
	13) echo "graphics engine exception (often a bad shader / illegal instruction)" ;;
	31) echo "MMU fault — GPU touched unmapped memory; usually the *consequence* of a hang" ;;
	43) echo "a channel was reset by the driver (app-level, GPU stays up)" ;;
	45) echo "preemptive channel teardown — normal when a hung app is killed" ;;
	48) echo "double-bit ECC error (hardware)" ;;
	62) echo "internal micro-controller halt" ;;
	63 | 64) echo "ECC page retirement / row remap (hardware degradation)" ;;
	69) echo "graphics engine class error" ;;
	79) echo "GPU FELL OFF THE BUS — link/power failure, not a software bug" ;;
	109) echo "CTX SWITCH TIMEOUT — GPU context wedged; this is the freeze" ;;
	119 | 120) echo "GSP firmware RPC timeout" ;;
	*) echo "see NVIDIA Xid reference" ;;
	esac
}

# Reader liveness. An absence claim is worthless if the reader is dead, so
# prove journalctl -k returns real content before reporting "no faults".
KLINES=$(journalctl -k -b 2>/dev/null | wc -l)
if [ "${KLINES:-0}" -lt 10 ]; then
	printf '%s: cannot read the kernel log (journalctl -k returned %s lines).\n' \
		"$PROG" "${KLINES:-0}" >&2
	printf '  Not the same as "no GPU faults" — this is a dead instrument.\n' >&2
	printf '  Add yourself to the systemd-journal group, or re-run with sudo.\n' >&2
	exit 3
fi

if [ "$SELF_TEST" -eq 1 ]; then
	printf 'kernel log reader OK: %s lines readable in this boot\n' "$KLINES"
	printf 'nvidia/NVRM lines present: %s\n' \
		"$(journalctl -k -b 2>/dev/null | grep -ciE 'nvidia|nvrm')"
	printf 'Xid lines present: %s\n' \
		"$(journalctl -k -b 2>/dev/null | grep -c 'Xid')"
	exit 0
fi

decode() {
	# stdin: raw journal lines. stdout: one annotated line per Xid.
	while IFS= read -r line; do
		case "$line" in
		*Xid*) ;;
		*) continue ;;
		esac
		num=$(printf '%s' "$line" | sed -nE 's/.*Xid \(PCI:[^)]*\): ([0-9]+).*/\1/p')
		when=$(printf '%s' "$line" | awk '{print $1, $2, $3}')
		who=$(printf '%s' "$line" | sed -nE 's/.*name=([^,]*).*/\1/p')
		[ -n "$num" ] || continue
		printf '%s  Xid %-3s  %s\n' "$when" "$num" "$(xid_meaning "$num")"
		[ -n "$who" ] && printf '                     process: %s\n' "$who"
	done
}

if [ -n "$SINCE" ]; then
	printf '== Xid faults since %s ==\n' "$SINCE"
	out=$(journalctl -k --since "$SINCE" 2>/dev/null | grep 'Xid' | decode)
else
	printf '== Xid faults this boot (since %s) ==\n' \
		"$(journalctl -k -b -o short-iso 2>/dev/null | head -1 | awk '{print $1}')"
	out=$(journalctl -k -b 2>/dev/null | grep 'Xid' | decode)
fi

if [ -n "$out" ]; then
	printf '%s\n' "$out"
	printf '\n-- %s fault(s). A 109 followed by a 31 on the same process is one hang. --\n' \
		"$(printf '%s\n' "$out" | grep -c 'Xid ')"
else
	printf 'none (reader verified live: %s kernel lines readable)\n' "$KLINES"
fi

if [ "$FOLLOW" -eq 1 ]; then
	printf '\n== following live — start the game now, Ctrl-C to stop ==\n'
	journalctl -k -f -n 0 2>/dev/null | grep --line-buffered 'Xid' | decode
fi
