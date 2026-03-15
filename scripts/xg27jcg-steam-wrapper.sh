#!/usr/bin/env bash
# Steam wrapper: switch XG27JCG to 2K (Frame Rate Boost) for game, restore previous config on exit.
# Usage: ./xg27jcg-steam-wrapper.sh %command%
# In Steam: set launch options to: /path/to/xg27jcg-steam-wrapper.sh %command%
#
# DDC toggle to 2K → run game → DDC toggle to 5K → gdctl restore (GNOME picks 4K otherwise).
# No gdctl needed when enabling 2K — GNOME handles res/scale automatically.

set -e

BUS="${XG27JCG_BUS:-5}"
XG27JCG_CONN="DP-2"
SECONDARY_CONN="DP-3"
SAVE_FILE="/tmp/xg27jcg-pre-game-state"

if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <game command and args>"
    echo "Example: $0 %command%"
    exit 1
fi

# Parse gdctl show for connector state
parse_state() {
    gdctl show 2>/dev/null | awk -v xg="$XG27JCG_CONN" -v sec="$SECONDARY_CONN" '
    /Monitor / { mconn=$2; gsub(/[()]/,"",mconn) }
    mconn==xg && /Current mode/ { getline; gsub(/.*──/,""); gsub(/^[[:space:]]+/,""); mode_xg=$0 }
    mconn==sec && /Current mode/ { getline; gsub(/.*──/,""); gsub(/^[[:space:]]+/,""); mode_sec=$0 }
    /Logical monitor/ { lm_scale="" }
    /Scale:/ { gsub(/.*Scale: /,""); lm_scale=$0 }
    /Monitors: \(/ { getline; if (lm_scale && $0 ~ xg) scale_xg=lm_scale; if (lm_scale && $0 ~ sec) scale_sec=lm_scale }
    END {
        print "MODE_XG=" mode_xg
        print "SCALE_XG=" (scale_xg ? scale_xg : "1.66")
        print "MODE_SEC=" mode_sec
        print "SCALE_SEC=" (scale_sec ? scale_sec : "1.0")
    }'
}

# Save current state
echo "Saving current display state..."
parse_state > "$SAVE_FILE"
source "$SAVE_FILE" 2>/dev/null || true

if [[ -z "$MODE_XG" || -z "$SCALE_XG" ]]; then
    echo "ERROR: Could not detect XG27JCG (${XG27JCG_CONN}) state. Is gdctl available?"
    exit 1
fi

# Already in 2K? (2560x1440)
if [[ "$MODE_XG" == 2560x1440@* ]]; then
    echo "Already in 2K mode. Running game without switching."
    exec "$@"
fi

echo "Current: $MODE_XG @ ${SCALE_XG}x scale"
echo "Switching to 2K (Frame Rate Boost)..."
# DDC toggle to 2K — GNOME handles res/scale automatically
ddcutil setvcp 0x03 1 --bus "$BUS" --noverify 2>/dev/null || true
ddcutil setvcp 0x03 20 --bus "$BUS" --noverify 2>/dev/null || true
# Wait for display to settle — game may span both monitors if launched too soon
sleep "${XG27JCG_SWITCH_DELAY:-2}"

echo "Running game..."
"$@"
GAME_EXIT=$?

echo "Restoring previous state: $MODE_XG @ ${SCALE_XG}x scale"

# DDC toggle back to 5K
ddcutil setvcp 0x03 1 --bus "$BUS" --noverify 2>/dev/null || true
ddcutil setvcp 0x03 20 --bus "$BUS" --noverify 2>/dev/null || true
sleep 1

# Restore GNOME config
if [[ -n "$MODE_SEC" && -n "$SCALE_SEC" ]]; then
    gdctl set -L -M "$XG27JCG_CONN" -m "$MODE_XG" -s "$SCALE_XG" -p \
           -L -M "$SECONDARY_CONN" --right-of "$XG27JCG_CONN" -s "$SCALE_SEC" 2>/dev/null
else
    gdctl set -L -M "$XG27JCG_CONN" -m "$MODE_XG" -s "$SCALE_XG" -p 2>/dev/null
fi

exit "$GAME_EXIT"
