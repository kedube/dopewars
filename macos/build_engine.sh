#!/bin/bash
# Compile the dopewars game engine (no networking / curses / gtk) into a
# static library for the native macOS app.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/src"
OBJ="$ROOT/macos/build/obj"
LIB="$ROOT/macos/build/libdopewars_engine.a"
mkdir -p "$OBJ"

GLIB_CFLAGS="$(pkg-config --cflags glib-2.0)"

CFLAGS=(-DHAVE_CONFIG_H
        "-I$ROOT/macos" "-I$SRC"
        $GLIB_CFLAGS
        -O2 -g
        -Wno-implicit-function-declaration)

# Engine translation units. dopewars.c supplies config/startup but its main()
# is renamed so the app can provide its own entry point.
ENGINE=(util tstring convert error log configfile message serverside AIPlayer sound admin network)

echo "Compiling engine..."
OBJS=()
for f in "${ENGINE[@]}"; do
  clang "${CFLAGS[@]}" -c "$SRC/$f.c" -o "$OBJ/$f.o"
  OBJS+=("$OBJ/$f.o")
done
clang "${CFLAGS[@]}" -Dmain=dopewars_unused_main -c "$SRC/dopewars.c" -o "$OBJ/dopewars.o"
OBJS+=("$OBJ/dopewars.o")

# The Cocoa URL helper and native sound driver.
clang "${CFLAGS[@]}" -c "$SRC/mac_helpers.m" -o "$OBJ/mac_helpers.o"
OBJS+=("$OBJ/mac_helpers.o")
clang "${CFLAGS[@]}" -c "$SRC/plugins/sound_cocoa.m" -o "$OBJ/sound_cocoa.o"
OBJS+=("$OBJ/sound_cocoa.o")

# The bridge that the Swift UI calls into.
clang "${CFLAGS[@]}" -c "$ROOT/macos/bridge/dpbridge.c" -o "$OBJ/dpbridge.o"
OBJS+=("$OBJ/dpbridge.o")

echo "Archiving $LIB"
rm -f "$LIB"
ar rcs "$LIB" "${OBJS[@]}"
echo "Done: $LIB"
