#!/bin/bash
# Builds Camera and installs it to /Applications, replacing a running copy.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh

# Ask a running copy to quit; an open menu can hold the request, so terminate it after 5 seconds.
# Otherwise `open` would just re-focus the old build.
# The same app was called BetterBooth before 0.4; it shares the bundle ID, so its copy goes too.
RUNNING='/Applications/(Camera|BetterBooth)\.app/Contents/MacOS/'
if pgrep -f "$RUNNING" >/dev/null; then
  osascript -e 'tell application id "com.muqsitnawaz.BetterBooth" to quit' >/dev/null 2>&1 || true
  for _ in $(seq 50); do
    pgrep -f "$RUNNING" >/dev/null || break
    sleep 0.1
  done
  pkill -TERM -f "$RUNNING" || true
fi
if [ -d /Applications/BetterBooth.app ]; then
  osascript -e 'tell application "Finder" to delete POSIX file "/Applications/BetterBooth.app"' >/dev/null
fi

ditto build/Camera.app /Applications/Camera.app
open /Applications/Camera.app
echo "installed /Applications/Camera.app"
