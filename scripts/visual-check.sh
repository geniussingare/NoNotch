#!/bin/zsh
# Screenshots every notch state using the Debug build's demo mode.
# Needs Screen Recording permission for the terminal running this script.
#   scripts/visual-check.sh [output-dir]
set -euo pipefail
ROOT=${0:A:h:h}
OUT=${1:-$ROOT/build/visual}
APP="$ROOT/build/Build/Products/Debug/noNotch.app/Contents/MacOS/noNotch"
mkdir -p "$OUT"

xcodebuild -scheme noNotch -configuration Debug -derivedDataPath "$ROOT/build" build -quiet

# Screen width in points; capture a 760×300 strip centred on the notch.
WIDTH=$(osascript -e 'tell application "Finder" to get item 3 of (get bounds of window of desktop)')
X=$(( (WIDTH - 760) / 2 ))

osascript -e 'quit app id "com.ganeshsingare.noNotch"' 2>/dev/null || true
sleep 1

for state in music banner hud home media video controls notes shelf clipboard calendar notifications; do
  "$APP" -demo "$state" >/dev/null 2>&1 &
  PID=$!
  sleep 2.2   # let the spring settle
  screencapture -x -R "$X,0,760,300" "$OUT/$state.png"
  kill "$PID" 2>/dev/null || true
  wait "$PID" 2>/dev/null || true
  echo "✓ $state"
done
echo "Screenshots in $OUT"
