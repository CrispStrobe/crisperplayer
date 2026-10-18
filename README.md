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
