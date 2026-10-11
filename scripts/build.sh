#!/bin/bash
# Builds build/BetterBooth.app: a universal (Apple silicon + Intel) release binary, Info.plist, icon,
# signed with hardened runtime. `--release` adds the secure timestamp notarization requires.
set -euo pipefail
cd "$(dirname "$0")/.."
TIMESTAMP=--timestamp=none
[ "${1:-}" = --release ] && TIMESTAMP=--timestamp

for arch in arm64 x86_64; do swift build -c release --arch $arch; done
rm -rf build/BetterBooth.app build/AppIcon.iconset
mkdir -p build/BetterBooth.app/Contents/MacOS build/BetterBooth.app/Contents/Resources
lipo -create -output build/BetterBooth.app/Contents/MacOS/BetterBooth \
  "$(swift build -c release --arch arm64 --show-bin-path)/BetterBooth" \
  "$(swift build -c release --arch x86_64 --show-bin-path)/BetterBooth"
cp Resources/Info.plist build/BetterBooth.app/Contents/Info.plist
swift scripts/make-icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o build/BetterBooth.app/Contents/Resources/AppIcon.icns

# Signed with your Developer ID if the keychain has one, so camera permission survives rebuilds.
# Otherwise ad hoc: it runs the same, but macOS asks for camera permission again after each rebuild.
IDENTITY=$(security find-identity -p codesigning -v | awk -F'"' '/Developer ID Application/ {print $2; exit}')
if [ "$TIMESTAMP" = --timestamp ] && [ -z "$IDENTITY" ]; then
  echo "build.sh --release needs a Developer ID Application identity in the keychain"; exit 1
fi
codesign --force --options runtime $TIMESTAMP --entitlements Resources/BetterBooth.entitlements \
  --sign "${IDENTITY:--}" build/BetterBooth.app
codesign --verify --strict build/BetterBooth.app
echo "built build/BetterBooth.app (signed: ${IDENTITY:-ad hoc})"
