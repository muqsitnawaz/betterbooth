#!/bin/bash
# Builds build/VertCam.app: a universal (Apple silicon + Intel) release binary, Info.plist, icon,
# signed with hardened runtime.
set -euo pipefail
cd "$(dirname "$0")/.."

for arch in arm64 x86_64; do swift build -c release --arch $arch; done
rm -rf build/VertCam.app build/AppIcon.iconset
mkdir -p build/VertCam.app/Contents/MacOS build/VertCam.app/Contents/Resources
lipo -create -output build/VertCam.app/Contents/MacOS/VertCam \
  "$(swift build -c release --arch arm64 --show-bin-path)/VertCam" \
  "$(swift build -c release --arch x86_64 --show-bin-path)/VertCam"
cp Resources/Info.plist build/VertCam.app/Contents/Info.plist
swift scripts/make-icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o build/VertCam.app/Contents/Resources/AppIcon.icns

# Signed with your Developer ID if the keychain has one, so camera permission survives rebuilds.
# Otherwise ad hoc: it runs the same, but macOS asks for camera permission again after each rebuild.
IDENTITY=$(security find-identity -p codesigning -v | awk -F'"' '/Developer ID Application/ {print $2; exit}')
codesign --force --options runtime --timestamp=none --entitlements Resources/VertCam.entitlements \
  --sign "${IDENTITY:--}" build/VertCam.app
codesign --verify --strict build/VertCam.app
echo "built build/VertCam.app (signed: ${IDENTITY:-ad hoc})"
