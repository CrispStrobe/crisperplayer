> Historical benchmark notes. Current chapter imports stream file headers; old readAsBytes/TODO observations below describe the earlier implementation. See README.md for current behavior.

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
- Chapter parse for jfk-test.m4a (98 KB) ~2 ms on desktop (legacy single-run, includes file I/O)

## Chapter parsing m4b benchmark

Benchmark script: `tool/bench_chapter_parse.dart` (`dart run tool/bench_chapter_parse.dart`).
Parses synthetic MP4 containers with Nero `chpl` (Go layout: version 0 + 7 reserved + count + 8B start100ns + title) under `moov.udta.chpl`, plus `mdat` dummy payload to simulate large audiobooks. Uses `ChapterParser.parseBytes` (memory) and `ChapterParser.parseFile` (file I/O). Environment:

```
Device: linux 3.12.1 | Dart 3.12.1 (stable) on "linux_x64"
Date: 2026-10-17T20:52:05
```

### parseBytes — header-only scan (mdat skipped via size field)

| Chapters | Header | Avg | Iterations | Notes |
|----------|--------|-----|------------|-------|
| 3 | 1.2 KB | 0.013 ms (12.5 µs) | 5000 | minimal audiobook |
| 10 | 1.4 KB | 0.007 ms (7.1 µs) | 5000 | typical podcast |
| 50 | 2.1 KB | 0.022 ms (22.1 µs) | 5000 | medium audiobook |
| 100 | 3.0 KB | 0.041 ms (41.3 µs) | 5000 | long audiobook |
| 500 | 10.8 KB | 0.093 ms (92.8 µs) | 1000 | very large TOC |
| 1000 | 20.6 KB | 0.116 ms (116.1 µs) | 1000 | pathological TOC |

`mdat` size has negligible effect — parser skips `mdat` via its 32-bit size header (O(1)), only `moov` is scanned. Verified across mdat payloads:

| Chapters | mdat | Total | Avg |
|----------|------|-------|-----|
| 3 | 10 KB | 10.2 KB | 0.003 ms (2.7 µs) |
| 3 | 100 KB | 100.2 KB | 0.003 ms (3.5 µs) |
| 3 | 1024 KB | 1024.2 KB | 0.003 ms (3.1 µs) |
| 10 | 10 KB | 10.3 KB | 0.006 ms (6.0 µs) |
| 10 | 100 KB | 100.3 KB | 0.010 ms (10.2 µs) |
| 10 | 1024 KB | 1024.3 KB | 0.008 ms (8.4 µs) |
| 50 | 10 KB | 11.1 KB | 0.024 ms (24.2 µs) |
| 50 | 100 KB | 101.1 KB | 0.021 ms (20.7 µs) |
| 50 | 1024 KB | 1025.1 KB | 0.024 ms (24.2 µs) |

`jfk-like 98KB synthetic 3ch: 0.003 ms (2.6 µs) over 5000 iters` — matches real jfk-test.m4a header-only scan; legacy 2 ms measurement included full decode probe overhead.

### parseFile — including file I/O (readAsBytes)

| Case | File size | Avg | Iterations |
|------|-----------|-----|------------|
| 10 chapters | 102.8 KB | 1.13 ms | 500 |
| 100 chapters | 104.5 KB | 1.01 ms | 500 |

Dominant cost is `File.readAsBytes` + temp file write; parse itself remains <0.1 ms. For >500 MB m4b, recommend `RandomAccessFile` streaming scan (TODO) to avoid loading `mdat` into memory — currently `readAsBytes` loads full file, but atom scan still O(header) after load. Target: `O(header)` memory via streamed header scan.

### Interpretation
- Linear O(n) in chapter count, O(1) in `mdat` size — scales to 1000 chapters <0.2 ms parse, <1.5 ms with I/O.
- Suitable for import pipeline: `LibraryService.importFiles` calls `ChapterParser.parseFile` only for single-file m4b/m4a; multi-file fallback uses per-file chapters without parse.
- No FFI, pure Dart `Uint8List` scan; 32/64-bit atom size handling + `meta` 4-byte offset covered.

Re-run: `nice -n 10 dart run tool/bench_chapter_parse.dart`

## Tips
- Large m4b >500 MB: stream scan via RandomAccessFile instead of readAsBytes (TODO)
- Web: GitHub Pages uses the separate local-file player in `site/`, with browser codec support and file-based tracks; the Flutter web target is an availability notice.
