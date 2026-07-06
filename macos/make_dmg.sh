#!/bin/bash
# Build the app and package it into a compressed, drag-to-install DMG:
# DopeWars-<version>-macOS-<arch>.dmg in macos/build/.
set -euo pipefail

MAC="$(cd "$(dirname "$0")" && pwd)"
BUILD="$MAC/build"
APP="$BUILD/Dope Wars.app"

bash "$MAC/build_app.sh"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' \
  "$APP/Contents/Info.plist")"
ARCH="$(uname -m)"
DMG="$BUILD/DopeWars-$VERSION-macOS-$ARCH.dmg"

# Stage the app next to an /Applications symlink for drag-to-install.
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# hdiutil is flaky right after image churn ("resource busy" / "resource
# temporarily unavailable", often from Spotlight/XProtect touching the new
# file), so retry both the create and the verify.
retry() {
  for attempt in 1 2 3; do
    "$@" && return 0
    [ "$attempt" = 3 ] && return 1
    echo "Retrying ($attempt failed): $*" >&2
    sleep 5
  done
}

rm -f "$DMG"
retry hdiutil create -volname "Dope Wars $VERSION" -srcfolder "$STAGING" \
  -format UDZO -ov "$DMG"

retry hdiutil verify "$DMG"
echo "Built: $DMG"
