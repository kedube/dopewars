/* Hand-written config.h for the native macOS (AppKit) build of dopewars.
 *
 * This build compiles the dopewars game engine WITHOUT networking, curses,
 * or GTK, so that it runs a purely in-process single-player game driven by a
 * native Cocoa UI (see macos/bridge and macos/DopewarsApp).
 */
#ifndef DOPEWARS_MACOS_CONFIG_H
#define DOPEWARS_MACOS_CONFIG_H

#define PACKAGE "dopewars"
#define VERSION "1.6.2"

/* Where read-only data (docs, sounds) would live; unused in this build but
 * referenced by the engine. Point at the app bundle Resources at runtime via
 * the bridge if needed. */
#define DPDATADIR "."
#define LOCALEDIR "."
#define DPDOCDIR "."
/* High score file lives in the user's Application Support dir; the bridge
 * overrides HiScoreFile at startup, so this default is rarely used. */
#define DPSCOREDIR "."

/* No networking: single-player, in-process client+server. */
/* #undef NETWORKING */

/* No text/graphical front-ends compiled into the engine. */
/* #undef CURSES_CLIENT */
/* #undef GUI_CLIENT */
/* #undef GUI_SERVER */

/* No native message translation. */
/* #undef ENABLE_NLS */

/* No sound backends (SoundInit becomes a no-op). */
/* #undef HAVE_SDL_MIXER */
/* #undef HAVE_ESD */
/* #undef HAVE_WINMM */

/* We use the Cocoa helper (mac_open_url). */
#define HAVE_COCOA 1

/* Platform capabilities available on modern macOS. */
#define HAVE_UNISTD_H 1
#define HAVE_FCNTL_H 1
#define HAVE_STDLIB_H 1
#define HAVE_SYS_TIME_H 1
#define HAVE_SYSLOG_H 1
#define HAVE_GETOPT 1
#define HAVE_GETOPT_LONG 1
#define HAVE_SELECT 1
#define HAVE_FORK 1
#define HAVE_GMTIME_R 1
#define HAVE_LOCALTIME_R 1
#define HAVE_ISSETUGID 1
#define HAVE_SOCKLEN_T 1
#define TIME_WITH_SYS_TIME 1

/* long long is supported by clang. */
#define SIZEOF_LONG_LONG 8

/* i18n macros are supplied by nls.h when ENABLE_NLS is undefined. */

#endif /* DOPEWARS_MACOS_CONFIG_H */
