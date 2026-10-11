#!/bin/bash
# Publishes the version in Resources/Info.plist as a GitHub release: builds with a secure timestamp,
# notarizes with Apple, staples the ticket, and uploads BetterBooth-<version>.zip.
# Needs a Developer ID identity and notarytool credentials in the environment:
# APPLE_ID, APPLE_TEAM_ID and APPLE_APP_SPECIFIC_PASSWORD.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
ZIP=build/BetterBooth-$VERSION.zip
NOTES=${1:?usage: release.sh <notes.md>}

./scripts/build.sh --release
ditto -c -k --keepParent build/BetterBooth.app "$ZIP"
xcrun notarytool submit "$ZIP" --wait \
  --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD"
xcrun stapler staple build/BetterBooth.app
# Zip again so the download carries the stapled ticket and opens offline.
rm -f "$ZIP"
ditto -c -k --keepParent build/BetterBooth.app "$ZIP"
spctl --assess --type execute build/BetterBooth.app

gh release create "v$VERSION" "$ZIP" --title "BetterBooth $VERSION" --notes-file "$NOTES"
