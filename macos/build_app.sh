#!/bin/bash
# Build the native macOS Dopewars.app: compile the C engine, then the Swift
# AppKit front-end, and assemble a standalone .app bundle.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAC="$ROOT/macos"
BUILD="$MAC/build"
APP="$BUILD/Dope Wars.app"

# 1. Engine static library.
bash "$MAC/build_engine.sh"

# 2. Compile the Swift front-end.
GLIB_CFLAGS="$(pkg-config --cflags glib-2.0)"
GLIB_LIBS="$(pkg-config --libs glib-2.0)"

SWIFT_SRC=(
  "$MAC/DopewarsApp/GameEngine.swift"
  "$MAC/DopewarsApp/Views.swift"
  "$MAC/DopewarsApp/MapView.swift"
  "$MAC/DopewarsApp/GameWindowController.swift"
  "$MAC/DopewarsApp/Dialogs.swift"
  "$MAC/DopewarsApp/AppDelegate.swift"
  "$MAC/DopewarsApp/main.swift"
)

mkdir -p "$BUILD"

echo "Compiling Swift app..."
swiftc \
  -O \
  -o "$BUILD/dopewars-bin" \
  -I "$MAC/bridge" \
  -Xcc -I"$MAC" -Xcc -I"$ROOT/src" -Xcc -DHAVE_CONFIG_H \
  $(for f in $GLIB_CFLAGS; do echo -Xcc "$f"; done) \
  "${SWIFT_SRC[@]}" \
  -L "$BUILD" -ldopewars_engine \
  $GLIB_LIBS \
  -framework AppKit -framework Foundation

# 3. Assemble the .app bundle.
echo "Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/dopewars-bin" "$APP/Contents/MacOS/Dope Wars"
cp "$MAC/Info.plist" "$APP/Contents/Info.plist"

# Bundle documentation and sounds if present.
if [ -d "$ROOT/doc" ]; then
  cp -R "$ROOT/doc" "$APP/Contents/Resources/doc" 2>/dev/null || true
fi
if [ -d "$ROOT/sounds" ]; then
  cp -R "$ROOT/sounds" "$APP/Contents/Resources/sounds" 2>/dev/null || true
fi
if [ -f "$MAC/AppIcon.icns" ]; then
  cp "$MAC/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# Make the app self-contained by bundling Homebrew dylibs and rewriting
# their load paths to @rpath.
bash "$MAC/bundle_libs.sh" "$APP"

# Ad-hoc code signature so Gatekeeper lets it run locally (after all
# install-name rewrites, which would otherwise invalidate the signature).
codesign --force --deep -s - "$APP" 2>/dev/null || true

echo "Built: $APP"
