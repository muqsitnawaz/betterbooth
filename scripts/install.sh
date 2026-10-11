#!/bin/bash
# Builds VertCam and installs it to /Applications, replacing a running copy.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh

# Ask a running copy to quit; an open menu can hold the request, so terminate it after 5 seconds.
# Otherwise `open` would just re-focus the old build.
if pgrep -f /Applications/VertCam.app/Contents/MacOS/VertCam >/dev/null; then
  osascript -e 'tell application id "com.muqsitnawaz.VertCam" to quit' >/dev/null 2>&1 || true
  for _ in $(seq 50); do
    pgrep -f /Applications/VertCam.app/Contents/MacOS/VertCam >/dev/null || break
    sleep 0.1
  done
  pkill -TERM -f /Applications/VertCam.app/Contents/MacOS/VertCam || true
fi

ditto build/VertCam.app /Applications/VertCam.app
open /Applications/VertCam.app
echo "installed /Applications/VertCam.app"
