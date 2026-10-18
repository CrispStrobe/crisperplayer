# CrisperPlayer

A local audiobook player built with Flutter, Riverpod, Drift, just_audio and audio_service.

## Current scope

- Android and iOS playback, with notification/lock-screen controls and background audio.
- Desktop playback using the native macOS backend or media_kit on Linux/Windows.
- Imports copy selected audio into application storage; deleting a book removes its managed copies, not the source files.
- Multi-file books use natural filename order and measured per-track durations. Unknown durations remain unknown until the decoder provides them.
- Resume positions, bookmarks and listening history are stored locally. Bookmarks restore the book and physical track as well as the position.
- M4B/M4A Nero chapter tables and embedded covers are parsed on device. QuickTime text-track chapters are not implemented.
- Configurable playback speed, volume, skip silence, seek interval, automatic bookmarks, startup restoration and theme. Decoder support for codecs and skip silence varies by platform.
- Sleep timers can pause immediately at expiry or at the end of the chapter playing when the countdown expires. Immediate chapter mode captures the current chapter boundary.
- JSON metadata export/import. Exports do not contain audio files; restoring on another device still requires accessible audio files.

Cloud sync and accounts are unavailable. The web build displays an availability notice; browser audio import, playback and persistent library storage are not supported in this version.

## Development

Use Flutter 3.44 or newer (Dart 3.12). The current dependencies require iOS 14 or newer; Android uses the Flutter SDK minimum.

```sh
flutter pub get
dart run build_runner build --build-filter lib/services/db/app_database.g.dart
flutter analyze
flutter test
flutter run -d <device-id>
```

The database upgrades version-one libraries in place. Legacy file references are adopted into app storage and their durations measured when first opened; unavailable source files must be re-imported.

The playback tests use the production coordinator and SQLite with an injected audio backend that preserves just_audio's pending `play()` future semantics. Native decoder, interruption and background behavior still require device testing:

```sh
flutter test integration_test/app_test.dart -d <device-id>
```

See [architecture](docs/ARCHITECTURE.md), [Android build](docs/ANDROID_BUILD.md), [iOS build](docs/IOS_BUILD.md), and [sync design](docs/CLOUD_SYNC.md).

## macOS and CLI

Run the desktop app with `flutter run -d macos`. On this Mac, clear inherited
Ruby overrides before Flutter commands that run CocoaPods:

```sh
env -u GEM_HOME -u GEM_PATH -u RUBYOPT flutter run -d macos
```

Desktop debug builds enable an authenticated loopback CLI. For a release build,
opt in with `--dart-define=CRISPERPLAYER_CLI=true`. The app must stay running:
the CLI controls its actual playback service and library.

```sh
dart run bin/crisperplayer.dart status
dart run bin/crisperplayer.dart import "/path/to/book.m4b"
dart run bin/crisperplayer.dart list
dart run bin/crisperplayer.dart play BOOK_ID
dart run bin/crisperplayer.dart pause
dart run bin/crisperplayer.dart seek 120
dart run bin/crisperplayer.dart speed 1.25
dart run bin/crisperplayer.dart bookmark "Start of chapter"
dart run bin/crisperplayer.dart bookmarks
dart run bin/crisperplayer.dart delete BOOK_ID
```

Commands return JSON; failures exit with code 1. `seek` uses seconds from the
start of the whole book. `import` streams files or recursively scanned folders
into the sandbox as one multi-track book, with natural filename order. It
creates managed copies and leaves source files untouched. `list.lastPositionMs` is the saved position within
the physical track; `status.positionMs` is the current position within the book.

The CLI exposes the GUI's library, playback, chapters, sleep timers, bookmarks,
history, settings, and metadata backup/restore operations. Use file paths and
JSON in place of file pickers and dialogs. `load BOOK_ID` opens a book paused.
Library search/filter/sort are available through `list --query`, `--filter`, and
`--sort`. `call COMMAND JSON_OBJECT` accepts structured arguments, including
bookmark notes. The desktop app continues to own audio and SQLite.

```sh
dart run bin/crisperplayer.dart import --title "My Book" --author "Author" "/path/to/tracks"
dart run bin/crisperplayer.dart chapters
dart run bin/crisperplayer.dart chapter 2
dart run bin/crisperplayer.dart sleep 900 --chapter-end
dart run bin/crisperplayer.dart settings themeMode dark
dart run bin/crisperplayer.dart bookmark-edit BOOKMARK_ID "New title" "Note"
dart run bin/crisperplayer.dart export library-backup.json
dart run bin/crisperplayer.dart restore library-backup.json
```

`clear-history` and `clear-bookmarks` require `--yes`. JSON backups contain
metadata and audio paths; audio files are not embedded in the backup.

Build a CLI executable with `dart build cli -o build/cli`, then run
`build/cli/bundle/bin/crisperplayer --help`. Keep the generated `bundle` folder
together when moving it. The CLI automatically finds the macOS connection file;
use `--control-file PATH` or `CRISPERPLAYER_CONTROL_FILE` to override discovery.
The connection file holds a per-run token and is private to the current user.

Run the native desktop integration test:

```sh
env -u GEM_HOME -u GEM_PATH -u RUBYOPT flutter test integration_test/desktop_test.dart -d macos
```

It uses an isolated on-disk library and generated WAV audio, the real native
decoder, the UI, and the CLI endpoint. It checks duration, advancing playback,
pause, seek, speed, bookmarks, history, and persistence after reopening SQLite.
Audio is muted during the test. It does not establish audible output quality,
Bluetooth routing, or mobile interruption/background behavior.

## App icon

The source artwork is in `assets/branding/`. Run
`python3 scripts/generate_icons.py` with ImageMagick 7 installed to regenerate
the iOS, macOS, Android legacy/adaptive, Windows, Linux, and web icon assets.
iOS icons are opaque; macOS uses a rounded tile; adaptive and maskable icons
keep the emblem inside their mask's safe area.
