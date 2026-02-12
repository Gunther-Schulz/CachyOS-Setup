#!/bin/bash
# Run FPS logger at 10 Hz, log to file. Stop with Ctrl+C.
# Build first: make -C ~/setup/fps-logger

LOG="${FPS_LOG:-$HOME/fps.log}"
DIR="$(dirname "$0")"

if [ ! -x "$DIR/fps_logger" ]; then
  echo "Build first: make -C $DIR"
  exit 1
fi

echo "Logging to $LOG (10 samples/sec). Stop with Ctrl+C."
echo "Start: $(date -Iseconds)" >> "$LOG"
"$DIR/fps_logger" 2>/dev/null | while IFS= read -r line; do
  echo "$(date '+%Y-%m-%d %H:%M:%S') $line"
done | tee -a "$LOG"
