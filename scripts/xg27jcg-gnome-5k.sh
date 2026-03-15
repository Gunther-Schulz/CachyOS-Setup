#!/usr/bin/env bash
# Force GNOME to use 5K (5120×2880) on XG27JCG (DP-2).
# Run after toggling Frame Rate Boost OFF — GNOME defaults to 4K otherwise.
#
# Layout: DP-2 (XG27JCG) primary left, DP-3 (Dell) right. Edit if your setup differs.
# Scale 1.66 (166%) by default.

gdctl set -L -M DP-2 -m 5120x2880@165.013 -s 1.66 -p \
       -L -M DP-3 --right-of DP-2 -s 1.0
