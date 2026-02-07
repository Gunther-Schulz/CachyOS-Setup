#!/bin/bash
# Run glxgears and log FPS with timestamps. SLOW: only one line every 5 seconds.
# For 10 samples/sec use: ~/setup/fps-logger/fps-log-run.sh
# Stop with Ctrl+C. Log: ~/glxgears-fps.log

LOG="${GLXGEARS_LOG:-$HOME/glxgears-fps.log}"

echo "Logging to $LOG (one line ~every 5s — for 10 Hz use ~/setup/fps-logger/fps-log-run.sh)"
echo "Stop with Ctrl+C. Start: $(date -Iseconds)" | tee -a "$LOG"

glxgears 2>&1 | while IFS= read -r line; do
  echo "$(date '+%Y-%m-%d %H:%M:%S') $line"
done | tee -a "$LOG"
