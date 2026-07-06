#!/bin/bash
# Make Dopewars.app self-contained by copying its Homebrew dylib dependencies
# into Contents/Frameworks and rewriting load commands to @rpath so the app
# runs on Macs without Homebrew. Written for the stock macOS bash 3.2.
set -euo pipefail

APP="${1:?usage: bundle_libs.sh path/to/App.app}"
# The executable is named after the bundle ("Dope Wars.app" -> "Dope Wars").
BIN="$APP/Contents/MacOS/$(basename "$APP" .app)"
FW="$APP/Contents/Frameworks"
mkdir -p "$FW"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
CLOSURE="$WORK/closure"   # newline-separated real paths, deduped

is_known() { grep -qxF "$1" "$CLOSURE" 2>/dev/null; }

# Print the /opt/homebrew deps of an object as resolved real paths.
homebrew_deps() {
  otool -L "$1" | tail -n +2 | awk '{print $1}' | while read -r dep; do
    case "$dep" in
      /opt/homebrew/*) readlink -f "$dep" 2>/dev/null || echo "$dep" ;;
    esac
  done
}

# Build the transitive closure starting from the binary.
: > "$CLOSURE"
PENDING="$WORK/pending"
homebrew_deps "$BIN" | sort -u > "$PENDING"

while [ -s "$PENDING" ]; do
  lib="$(head -n 1 "$PENDING")"
  tail -n +2 "$PENDING" > "$PENDING.tmp"; mv "$PENDING.tmp" "$PENDING"
  if is_known "$lib"; then continue; fi
  echo "$lib" >> "$CLOSURE"
  homebrew_deps "$lib" >> "$PENDING"
  sort -u "$PENDING" > "$PENDING.tmp"; mv "$PENDING.tmp" "$PENDING"
done

echo "Bundling $(wc -l < "$CLOSURE" | tr -d ' ') dylibs into $FW"

# Copy each lib and set its own id to @rpath.
while read -r src; do
  base="$(basename "$src")"
  cp -f "$src" "$FW/$base"
  chmod u+w "$FW/$base"
  install_name_tool -id "@rpath/$base" "$FW/$base"
done < "$CLOSURE"

# Rewrite references within each bundled lib and the binary.
rewrite_refs() {
  local obj="$1"
  otool -L "$obj" | tail -n +2 | awk '{print $1}' | while read -r dep; do
    case "$dep" in
      /opt/homebrew/*)
        real="$(readlink -f "$dep" 2>/dev/null || echo "$dep")"
        if is_known "$real"; then
          install_name_tool -change "$dep" "@rpath/$(basename "$real")" "$obj"
        fi
        ;;
    esac
  done
}

while read -r src; do
  rewrite_refs "$FW/$(basename "$src")"
done < "$CLOSURE"
rewrite_refs "$BIN"

# Ensure the binary can find @rpath libs (ignore if the rpath already exists).
install_name_tool -add_rpath "@executable_path/../Frameworks" "$BIN" 2>/dev/null || true

echo "Done bundling."
