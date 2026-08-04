#!/bin/bash
# openrgb-sleep.sh — all RGB dark during sleep, the profile restored on wake.
#
# Install (as the systemd-sleep hook; the name keeps it alphabetically before
# spd5118.sh so the pre-sleep RAM write happens with the SPD driver still loaded —
# the same conditions under which OpenRGB demonstrably controls the DIMMs):
#
#   sudo install -m755 rgb/openrgb-sleep.sh /etc/systemd/system-sleep/openrgb.sh
#
# WHY EACH HALF EXISTS (verified live, 2026-08-05):
#   pre:  the DIMM RGB controllers keep standby power in S3 and retain their last
#         command — that is why the RAM stayed lit through every sleep. Told black,
#         they stay black the same way. This deliberately uses -c on ALL devices
#         rather than a profile: off.orp silently lacked the RAM entirely, and a
#         profile also silently skips any device whose stored identity has drifted
#         (see the doc). A direct broadcast cannot miss anything.
#   post: the motherboard and GPU controllers LOSE power in S3 and reset to their
#         firmware rainbow default — re-applying the profile is what removes the
#         rainbow. The sleep gives USB re-enumeration time to finish first.
#
# Runs as the desktop user: that is the proven access path (udev-granted i2c and
# hidraw), and it reads the user's own profile store.

RGB_USER=g
PROFILE="my profile"

case $1 in
  pre)
    timeout 30 runuser -u "$RGB_USER" -- openrgb -m direct -c 000000 >/dev/null 2>&1
    ;;
  post)
    sleep 5
    timeout 30 runuser -u "$RGB_USER" -- openrgb -p "$PROFILE" >/dev/null 2>&1
    ;;
esac
exit 0
