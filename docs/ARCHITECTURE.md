# CrisperPlayer — Architecture & Framework Decision

## Why Flutter (like CrisperWeaver)

**Decision: Flutter** — same stack as `../../CrisperWeaver` (aka CrisperWeaver). Rationale vs alternatives:

| Criterion | Flutter | React Native / Expo | Capacitor / Ionic | Tauri-mobile |
|-----------|---------|---------------------|-------------------|--------------|
| Single codebase for Android+iOS+desktop+web | ✓ one Dart codebase, proven in CrisperWeaver (android/ios/macos/windows/linux/web → web-e2e) | JS bridge, fragmented audio libs | WebView wrapper, poor background audio | not yet mature mobile |
| Audio formats (m4b/m4a/mp3/flac/ogg/wav/aac/opus/wma/aiff) | **just_audio** delegates to ExoPlayer (Android) + AVPlayer (iOS) → native decoders handle m4b as m4a + chapter metadata; `just_audio_media_kit` covers desktop via libmpv | expo-av / react-native-track-player cover less (m4b spotty), require native bridges per codec | Web Audio API can't decode m4b in WebView | — |
| Background / lockscreen controls | **audio_service + just_audio_background** — notification, Control Center, headset buttons, ducking/interruptions | similar but second-class, needs extra native config | no reliable background | — |
| State & storage | Riverpod + Drift (SQLite) — typed, migratable, already used in CrisperWeaver batch/history services; `shared_preferences` for settings | Redux/MMVM, AsyncStorage — less typed | same | — |
| Team reuse | Direct reuse: `audio_session` config, permission_handler, file_picker, path_provider, uuid/intl patterns, theme, build scripts | rewrite | rewrite | rewrite |

**Conclusion:** stay in Flutter. CrisperWeaver already solves the hard parts — permissions, file pick, audio session, background, desktop fallback. CrisperPlayer reuses that skeleton and extends it for audiobook-specific needs.

## App structure (mirrors CrisperWeaver)

```
lib/
  main.dart            — binding init, AudioSession (speech), SharedPrefs, Drift DB, PlaybackService init, ProviderScope + GoRouter
  theme/app_theme.dart — Material 3 light/dark (seed = Crisp blue), cards, appbar
  models/              — Book, Chapter, Bookmark, PlaybackState, ListeningSession (uuid, json, copyWith)
  services/db/         — Drift: books, chapters, bookmarks, listeningHistory; watchAll/watchSingle, ON DELETE CASCADE
  services/
    library_service.dart   — file_picker (m4b…mka), infer title, probe duration via throwaway AudioPlayer, chaptersFromFiles, updateProgress
    bookmark_service.dart  — manual (title+note+chapterIndex) + auto (every 5 min + on pause/seek), pruneAuto(keep 20)
    history_service.dart   — startSession/endSession (wall clock), watchAll/recent/forBook
    settings_service.dart  — SharedPreferences wrapper (speed/volume/autoBookmark/skipSilence/seek/theme/resume)
    audio/
      playback_service.dart — AudioPlayer + AudioSession + ConcatenatedAudioSource (multi-file books), position/seek/skip/speed/volume/sleepTimer, persist every 2s, bookPosition = bookOffset+player.position, next/prev track
      audio_handler.dart    — BaseAudioHandler for lockscreen (optional, wired if audio_service enabled)
  providers/providers.dart — Riverpod: appDatabase, library/bookmark/history/settings/playback, watchAllBooks/watchBook/watchChapters/watchBookmarks/watchHistory, selectedBookId
  screens/
    library_screen.dart — grid (2 cols), search, filter all/recent/finished, progress bar, import FAB (single vs separate), delete via drift cascade
    player_screen.dart  — cover, title/author, chapter indicator, slider + time, chapter markers, play/pause/skip±30/next/prev, speed (0.5–3x), sleep timer (15/30/60/off), bookmark FAB, chapter drawer
    bookmarks_screen.dart — sorted desc, tap seek, edit/delete popup
    history_screen.dart — grouped by day, when-we-played-what (start/end/listened/bookPos), tap → player
    settings_screen.dart — speed/skipSilence/seek/autoBookmark/resumeOnLaunch/theme
  widgets/ book_card, mini_player, chapter_tile, bookmark_tile
  utils/ format (hh:mm:ss, relative date), platform_utils
```

## Key design choices for audiobooks

### m4b and common formats
m4b ≡ m4a (AAC) + chapter metadata. Native decoders already handle it — ExoPlayer/AVPlayer decode AAC/MP3/ALAC transparently. We treat m4b as `AudioSource.uri(Uri.file(path))`; chapter parsing is layered on top: `chaptersFromFiles` creates one chapter per file; for single-file m4b, a future pass can call a native MP4 chapter parser (FFI) to replace the single entry with real chapter table. This keeps MVP shippable while preserving extension point.

Desktop uses `just_audio_media_kit` (libmpv) so Linux/Windows/macOS play the same files without extra codec work.

### Resume & when-we-played-what
On every `loadBook`, we read `books.lastPositionFilePath/lastPositionMs` and `seek(index, pos)`. During playback, a 2-second timer calls `library.updateProgress` → Drift `books` row with `lastPlayedAtMs`, `lastPositionFilePath`, `totalProgress` (bookPos/total). On pause/stop/completed/error we also persist + create auto-bookmark + end history session. On app launch, `resumeOnLaunch` can auto-load last played book.

History: `listeningHistory` writes `startSession` on play (startMs, speed) and `updateHistoryEnd` on pause/stop (endMs, listenedMs). `history_screen.dart` groups by day and shows "when we played what" — tap jumps to book.

### Auto + manual bookmarking
- **Manual:** FAB in player → dialog title+note → `bookmark_service.addManual` with filePath/position/bookPosition/chapterIndex.
- **Auto:** 5-minute ticker + onPause/onSeek trigger → `addAuto` (title "Auto hh:mm:ss"), then `pruneAuto(keep 20)` to avoid unbounded growth. Drift query (`where bookId == X order by createdAt desc`) feeds `bookmarks_screen.dart`; tap seeks via `playback.seek(pos)`.

### Sleep timer & extras
`PlaybackService.setSleepTimer(Duration, endOfChapter)` ticks every second; on zero calls `pause()`. UI is a `PopupMenuButton` in player appbar (15/30/60/off). Speed is a slider 0.5–3× → `player.setSpeed`. Skip ±30 s (configurable via settings) uses `player.seek(position ± sec)`.

## Cross-platform notes

- **Android:** `android/app/src/main/AndroidManifest.xml` needs `<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />` + `android.permission.POST_NOTIFICATIONS` for audio_service notification (permission_handler requests). `just_audio_background` adds `android:enableOnBackInvokedCallback` already.
- **iOS:** `ios/Runner/Info.plist` needs `UIBackgroundModes = audio` + `NSAppleMusicUsageDescription` (if media library) and microphone not needed. `audio_session` configures `AVAudioSessionCategory.playback`.
- **Desktop/web:** `just_audio_media_kit` + `sqlite3_flutter_libs` ship native libs; no extra code — same Dart.

## Build & run

```bash
flutter pub get
dart run build_runner build -d       # generate drift *.g.dart
flutter run -d android|ios|macos
flutter build apk --release
flutter build ios --release
```

All data stays on device (like CrisperWeaver offline-first) — no network.
