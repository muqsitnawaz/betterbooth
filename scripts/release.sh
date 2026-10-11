#!/bin/bash
# Publishes the version in Resources/Info.plist as a GitHub release: builds with a secure timestamp,
# notarizes with Apple, staples the ticket, and uploads Camera-<version>.zip.
# Needs a Developer ID identity and notarytool credentials in the environment:
# APPLE_ID, APPLE_TEAM_ID and APPLE_APP_SPECIFIC_PASSWORD.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
ZIP=build/Camera-$VERSION.zip
NOTES=${1:?usage: release.sh <notes.md>}
: "${APPLE_ID:?}" "${APPLE_TEAM_ID:?}" "${APPLE_APP_SPECIFIC_PASSWORD:?}"
# The release must be exactly the pushed main: a clean tree, HEAD on origin/main, a new tag.
git fetch -q origin
[ -z "$(git status --porcelain)" ] || { echo "release.sh: commit or discard local changes first"; exit 1; }
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "release.sh: HEAD is not origin/main"; exit 1; }
! git ls-remote --exit-code --tags origin "v$VERSION" >/dev/null || { echo "release.sh: v$VERSION is already released"; exit 1; }

./scripts/build.sh --release
ditto -c -k --keepParent build/Camera.app "$ZIP"
xcrun notarytool submit "$ZIP" --wait \
  --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD"
xcrun stapler staple build/Camera.app
# Zip again so the download carries the stapled ticket and opens offline.
rm -f "$ZIP"
ditto -c -k --keepParent build/Camera.app "$ZIP"
spctl --assess --type execute build/Camera.app

gh release create "v$VERSION" "$ZIP" --target "$(git rev-parse HEAD)" --title "Camera $VERSION" --notes-file "$NOTES"
