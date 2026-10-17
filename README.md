# CrisperPlayer

Versatile cross-platform audiobook player — Flutter, like CrisperWeaver.

## Why Flutter

Single Dart codebase for Android+iOS+desktop+web, proven in CrisperWeaver. just_audio delegates to ExoPlayer (Android) + AVPlayer (iOS) — native decoders handle m4b/m4a/mp3/flac/ogg/wav/aac/opus/wma/aiff and more. just_audio_media_kit (libmpv) covers Linux/Windows/macOS. Background/lockscreen via audio_service + audio_session (speech). Riverpod + Drift (SQLite) for library/history/bookmarks; shared_preferences for settings. Direct reuse of CrisperWeaver patterns.

See docs/ARCHITECTURE.md for decision matrix.

## Features

- Library: import via file_picker (single or multi-file books), title/author inference, duration probe, grid with progress, search/filter, delete (DB cascade)
- Playback: ConcatenatingAudioSource queue per book, resume from lastPosition, bookPosition = bookOffset + player.position, skip +/-30s, next/prev, speed 0.5-3x, sleep timer (15/30/60/off)
- Resume & history: 2s persist timer, listeningHistory startSession/endSession, history grouped by day shows when we played what
- Bookmarks: manual (FAB title+note) + auto (5min ticker + on pause) -> pruneAuto(20), tap seek, edit/delete
- Chapters: one per file MVP; single-file m4b hook for real MP4 chapter table via FFI
- Settings: speed, skipSilence, seek interval, autoBookmark, resumeOnLaunch, theme

## Supported formats

m4b = m4a (AAC) + chapters. Native decoders handle m4b as m4a. Common: m4b, m4a, mp3, flac, ogg, wav, aac, opus, wma, aiff/aif, mp2, mov, webm, 3gp, mkv/mka. Desktop via just_audio_media_kit.

## Getting started

```
flutter pub get
dart run build_runner build
flutter run -d android   # or ios, macos, linux, chrome
flutter build apk --release
flutter build ios --release
flutter build web --no-wasm-dry-run
```

Android: FOREGROUND_SERVICE + POST_NOTIFICATIONS + READ_MEDIA_AUDIO in manifest. iOS: UIBackgroundModes audio in Info.plist.

All data on device, offline-first.
