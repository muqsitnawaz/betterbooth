#!/bin/bash
# Builds BetterBooth and installs it to /Applications, replacing a running copy.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh

# Ask a running copy to quit; an open menu can hold the request, so terminate it after 5 seconds.
# Otherwise `open` would just re-focus the old build.
if pgrep -f /Applications/BetterBooth.app/Contents/MacOS/BetterBooth >/dev/null; then
  osascript -e 'tell application id "com.muqsitnawaz.BetterBooth" to quit' >/dev/null 2>&1 || true
  for _ in $(seq 50); do
    pgrep -f /Applications/BetterBooth.app/Contents/MacOS/BetterBooth >/dev/null || break
    sleep 0.1
  done
  pkill -TERM -f /Applications/BetterBooth.app/Contents/MacOS/BetterBooth || true
fi

ditto build/BetterBooth.app /Applications/BetterBooth.app
open /Applications/BetterBooth.app
echo "installed /Applications/BetterBooth.app"
