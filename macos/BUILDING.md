# Building Dope Wars for macOS

Instructions for building the native AppKit port from source. The result is
a self-contained, ad-hoc-signed `Dope Wars.app` that runs on Macs without
Homebrew installed.

## Prerequisites

- **macOS 11 (Big Sur) or later** (the deployment target set in `Info.plist`)
- **Xcode Command Line Tools** — provides `clang`, `swiftc`, `ar`,
  `install_name_tool`, and `codesign`:

  ```sh
  xcode-select --install
  ```

- **Homebrew** with glib and pkg-config (the engine uses glib for strings,
  lists, and config parsing):

  ```sh
  brew install glib pkg-config
  ```

> **Apple Silicon vs. Intel:** the dylib-bundling step scans for
> dependencies under `/opt/homebrew` (Apple Silicon's Homebrew prefix). On
> an Intel Mac (`/usr/local`), the app still builds and runs locally, but
> `bundle_libs.sh` won't pick up the glib dylibs — extend its path matching
> if you need a self-contained Intel build.

## Quick start

```sh
cd macos
./build_app.sh
open "build/Dope Wars.app"
```

That's the whole build. It is fully scripted — no Xcode project, no
`configure`. Rerunning `build_app.sh` after source changes rebuilds
everything (the engine compiles in a few seconds).

## What the build does

`build_app.sh` runs five steps:

1. **Engine** (`build_engine.sh`) — compiles the original dopewars C engine
   into `build/libdopewars_engine.a` using the hand-written `macos/config.h`
   (networking, curses, and GTK are compiled out, so the engine runs as an
   in-process single-player client+server). It also compiles:
   - `src/mac_helpers.m` — Cocoa URL helper,
   - `src/plugins/sound_cocoa.m` — the native sound driver,
   - `bridge/dpbridge.c` — the C bridge the Swift UI talks to.
   `src/dopewars.c` is compiled with `-Dmain=dopewars_unused_main` so the
   app supplies its own entry point.
2. **Swift front-end** — `swiftc` compiles everything in `DopewarsApp/`
   (except the `.devonly` test harness) and links it against the engine
   archive and glib. The C bridge is imported through
   `bridge/module.modulemap` as the `DopewarsBridge` module.
3. **Bundle assembly** — creates `build/Dope Wars.app`, copying the binary
   to `Contents/MacOS/Dope Wars`, plus `Info.plist`, the icon, docs, and the
   `sounds/` WAVs into `Contents/Resources`.
4. **Dylib bundling** (`bundle_libs.sh`) — computes the transitive Homebrew
   dylib closure of the binary (glib, gettext, pcre2), copies it into
   `Contents/Frameworks`, and rewrites all load commands to `@rpath` with
   `install_name_tool`, so the app runs on machines without Homebrew.
5. **Signing** — ad-hoc `codesign` *after* the install-name rewrites (which
   would otherwise invalidate the signature).

## Layout

| Path | Contents |
| ---- | -------- |
| `config.h` | Hand-written engine build config (no networking/curses/GTK) |
| `bridge/dpbridge.c`, `bridge/dpbridge.h` | C bridge: starts the game, decodes protocol messages into events, exposes state accessors and actions. No glib types cross this boundary. |
| `bridge/module.modulemap` | Imports the bridge into Swift as `DopewarsBridge` |
| `DopewarsApp/*.swift` | The AppKit UI (engine wrapper, views, main window, dialogs, subway map, app delegate) |
| `Info.plist`, `AppIcon.icns` | Bundle metadata and icon |
| `build_engine.sh`, `build_app.sh`, `bundle_libs.sh` | The three build scripts (all plain bash) |
| `build/` | All build products (safe to delete for a clean rebuild) |

## Testing

### Engine/bridge tests (C, headless)

`bridge/` contains event-driven harnesses that play the real game through
the bridge with no UI: `smoketest.c`, `interactiontest.c` (full interaction
coverage), `gunlesstest.c` (gunless fights), and `gunbuytest.c` (coat-space
regression). Build and run one like this:

```sh
cd macos
./build_engine.sh
clang -I. -Ibridge -I../src -DHAVE_CONFIG_H \
  $(pkg-config --cflags glib-2.0) -O0 -g \
  bridge/interactiontest.c build/libdopewars_engine.a \
  $(pkg-config --libs glib-2.0) \
  -framework AppKit -framework Foundation -o build/interactiontest
./build/interactiontest
```

> Run the build lines through `bash` (or a script) rather than pasting into
> zsh functions with unquoted variables — the `pkg-config` output must stay
> word-split exactly as shown.

### UI test (Swift, headless)

`DopewarsApp/uiauto_main.swift.devonly` drives the real
`GameWindowController` offscreen — it clicks the actual buttons via
`performClick`, answers prompts, fights, trades, and hit-tests the prompt
and fight panels to guard against dead-layout regressions. Build it by
compiling the app sources *without* `AppDelegate.swift`/`main.swift` and
with the harness as `main.swift`:

```sh
cd macos
mkdir -p /tmp/uiautosrc
cp DopewarsApp/uiauto_main.swift.devonly /tmp/uiautosrc/main.swift
swiftc -o build/uiautotest -I bridge \
  -Xcc -I"$PWD" -Xcc -I"$PWD/../src" -Xcc -DHAVE_CONFIG_H \
  $(for f in $(pkg-config --cflags glib-2.0); do echo -Xcc "$f"; done) \
  DopewarsApp/GameEngine.swift DopewarsApp/Views.swift \
  DopewarsApp/MapView.swift DopewarsApp/GameWindowController.swift \
  DopewarsApp/Dialogs.swift /tmp/uiautosrc/main.swift \
  -L build -ldopewars_engine $(pkg-config --libs glib-2.0) \
  -framework AppKit -framework Foundation
./build/uiautotest        # prints "UIAUTO OK" on success
```

## Runtime data

| What | Where |
| ---- | ----- |
| High scores | `~/Library/Application Support/Dopewars/dopewars.sco` |
| Preferences (appearance, mute, dealer name, market-intel toggles, game rules, window frame) | `defaults read io.sourceforge.dopewars.macos` |

## DMG packaging and GitHub releases

`make_dmg.sh` builds the app and packages it into a compressed
drag-to-install disk image (with an `/Applications` symlink) at
`build/DopeWars-<version>-macOS-<arch>.dmg`; the version comes from
`Info.plist`:

```sh
cd macos
./make_dmg.sh
```

The `.github/workflows/macos-release.yml` pipeline runs this on an Apple
Silicon GitHub runner. Pushing a version tag (e.g. `1.6.2` or `v1.6.2`)
builds the DMG
and attaches it to a GitHub release for that tag (creating the release
with generated notes if it doesn't exist). The workflow can also be run
manually from the Actions tab, which uploads the DMG as a workflow
artifact without making a release.

## Distributing to other Macs

The build is only **ad-hoc signed**, which is fine for the machine that
built it. On another Mac, Gatekeeper will quarantine a downloaded copy;
either right-click → Open the first time, or clear the quarantine flag
(`xattr -dr com.apple.quarantine "Dope Wars.app"`). For real distribution
you'd re-sign with a Developer ID certificate and notarize:

```sh
codesign --force --deep --options runtime -s "Developer ID Application: …" "build/Dope Wars.app"
```

## Troubleshooting

- **`pkg-config: command not found` / glib not found** — install the
  prerequisites above; check `pkg-config --modversion glib-2.0` prints a
  version.
- **Strange link or module errors after pulling changes** — clean rebuild:
  `rm -rf macos/build && ./build_app.sh`.
- **App builds but won't launch from Finder** — check the signature
  (`codesign -v "build/Dope Wars.app"`); `bundle_libs.sh` must run *before*
  signing, which `build_app.sh` already guarantees.
- **No sound** — the WAVs come from the repo's `sounds/` directory into
  `Contents/Resources/sounds`; confirm they were present at build time.
