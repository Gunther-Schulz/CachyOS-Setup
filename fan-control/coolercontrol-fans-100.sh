#!/usr/bin/env bash
# Set Motherboard (NCT6799) fans to 100%.
# Usage: coolercontrol-fans-100.sh [1|2|both]
#   1   = fan1 only (P12)
#   2   = fan2 only (Silent Wings 4)
#   both = both fans (default)
# Requires: curl, coolercontrold on CC_URL (default localhost:11987).

OPT="${1:-both}"
case "$OPT" in
  1|2|both) ;;
  -h|--help) echo "Usage: $0 [1|2|both]"; echo "  1=fan1 (P12), 2=fan2 (Silent Wings 4), both=default"; exit 0 ;;
  *) echo "Unknown option: $OPT (use 1, 2, or both)"; exit 1 ;;
esac

CC_URL="${CC_URL:-http://localhost:11987}"
CC_USER="${CC_USER:-CCAdmin}"
CC_PASS="${CC_PASS:-coolAdmin}"
NCT6799_UID="00a4da18625f56275c89e2fcd25a83c08c5ad3326452fa7e252fcc8a89c92493"
COOKIE="/tmp/cc_cookies_$$"

cleanup() { rm -f "$COOKIE"; }
trap cleanup EXIT

curl -s -c "$COOKIE" -X POST -u "$CC_USER:$CC_PASS" "$CC_URL/login" -o /dev/null || { echo "Login failed"; exit 1; }

if [[ "$OPT" == "1" || "$OPT" == "both" ]]; then
  curl -s -b "$COOKIE" -X PUT -H "Content-Type: application/json" -d '{"speed_fixed":100}' "$CC_URL/devices/$NCT6799_UID/settings/fan1/manual" -w "fan1 (P12): %{http_code}\n" -o /dev/null
fi
if [[ "$OPT" == "2" || "$OPT" == "both" ]]; then
  curl -s -b "$COOKIE" -X PUT -H "Content-Type: application/json" -d '{"speed_fixed":100}' "$CC_URL/devices/$NCT6799_UID/settings/fan2/manual" -w "fan2 (Silent Wings 4): %{http_code}\n" -o /dev/null
fi
echo "Done. Run coolercontrol-fans-revert.sh [1|2|both] to restore Default Profile."
