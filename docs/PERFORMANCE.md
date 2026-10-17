# Performance

## Playback
- Probe duration via throwaway AudioPlayer (header-only, <4s timeout per file, not decoding)
- Chapter parse: single-pass MP4 atom scan (32/64-bit + meta offset), O(n) over file header only, not full mdat
- Cover: same scan, writes to systemTemp/crisper_covers, no FFI, JPEG/PNG via magic
- Preloading: ConcatenatingAudioSource queue per book, no extra isolate (future: prefetch next book)

## Drift
- Indexes: books.id, chapters.bookId, bookmarks.bookId, history.bookId + startedAtMs
- Batch insert for chapters, insertOrReplace for import, no N+1 in library sort (in-memory sort after watch)
- Memory: NativeDatabase.memory() in tests, sqlite3_flutter_libs on device

## Measuring
- `lib/utils/performance.dart` helper: `measure(String label, Future Function())` logs ms via Stopwatch
- Chapter parse for jfk-test.m4a (98 KB) ~2 ms on desktop

## Tips
- Large m4b >500 MB: stream scan via RandomAccessFile instead of readAsBytes (TODO)
- Web: just_audio_web decodes via browser, no native m4b chapters (fallback to 1 chapter)
