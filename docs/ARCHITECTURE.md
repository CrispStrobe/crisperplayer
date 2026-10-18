# Architecture

Flutter renders the UI; Riverpod owns service lifetimes and exposes Drift queries and observable settings. Drift is the local source of truth. There is no cloud authentication or sync implementation in the shipped application.

## Playback

`PlaybackService` serializes UI, lifecycle and native media commands. Its `AudioBackend` boundary has a just_audio implementation and a deterministic test implementation. A single native `AudioPlayer` is shared with `CrisperAudioHandler`, which publishes media metadata and delegates controls to the coordinator.

The application awaits playback initialization before rendering. Windows/Linux register media_kit before creating any players. Android's activity extends `AudioServiceActivity` so background playback uses the same Flutter engine. Native initialization failures surface as startup errors.

`play()` requests playback without awaiting the long-lived just_audio playback future. Ready/playing events open a listening session; pauses, buffering and completion close it. Sessions use a monotonic stopwatch and checkpoint into SQLite every two seconds. Backgrounding checkpoints without ending an ongoing session. Book changes save and close the old session before replacing its queue.

A physical track and an embedded chapter are distinct concepts. `book_tracks` stores ordered file paths and nullable measured durations. Whole-book seeks and skips use those durations; file bookmarks retain their book, file and local offset. No equal-duration estimates or fabricated 30-minute tracks are used. Unknown durations prevent whole-book seeks past the unknown segment until timing is available.

Chapter-end sleep captures a fixed endpoint when entering chapter mode. Subsequent position and index events compare against that endpoint, including ticks that cross directly into the next chapter. The countdown and production pause path are shared with tests.

## Storage and imports

Library imports validate source availability, naturally sort filenames, stream-copy files into `<application-support>/library/<book-id>/`, probe durations and write books, tracks and chapters in a transaction. Import failure removes the managed copies. Deletion stops the active book, removes related metadata atomically and deletes only that book's managed directory.

Schema version two adds `book_tracks`; schema three adds series/collection fields, validated per-book playback overrides, manual reading-status overrides and `playback_queue`. Earlier rows and positions remain intact. The first load adopts legacy files into managed storage, remaps chapter/bookmark/resume paths and probes timing. Missing legacy files produce an actionable error instead of silently replacing their timing.

MP4 metadata extraction seeks past audio payload atoms and reads only the `moov` atom, with a 32 MB limit. Covers live alongside their managed book files. Nero and referenced QuickTime text-track chapters are supported. QuickTime sample tables and text reads are bounded, with stco/co64 offsets, Unicode titles and common edit-list timing. ID3v2.3/v2.4 text and artwork reads are capped at 16 MB of tag data.

Metadata exports include schema version, tracks, organization, per-book preferences and queue order. Imports reject unsupported versions and apply updates atomically using upserts, avoiding SQLite REPLACE's delete-and-cascade behavior. Audio is not embedded in JSON.

## Settings and shares

`SettingsService` is a ChangeNotifier backed by SharedPreferences. Riverpod observes it for theme and settings UI; playback observes it for player configuration, seek intervals and automatic bookmarks. Startup restoration loads the last played book paused when enabled. Per-book speed, skip silence, seek interval and smart rewind inherit these defaults unless explicitly overridden. Player speed changes update the current book override.

The coordinator advances the persistent book queue only on playing completion and without a pending sleep timer. Failed loads retain their queue entry; successful loads remove it. The player follows CLI and queue book changes without reloading or pausing the new book.

Share intake accepts cold and warm shares, supports callback rebinding and serializes imports. Identical simultaneous deliveries share one import. The native stream and reset operations are injectable for regression tests.

## Platform scope

Installed Android, iOS and desktop apps use local filesystem storage. The browser build displays an explicit availability notice before initializing native storage or playback. It is not a browser player. Cloud sync is unavailable; `CLOUD_SYNC.md` records design requirements for a future authenticated implementation.
