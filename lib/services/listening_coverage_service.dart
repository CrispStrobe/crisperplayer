import 'dart:async';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../models/listening_coverage.dart';
import 'db/app_database.dart';

/// Reads the durable union of confirmed playback, never guessed coverage from
/// a resume offset, finished flag, or historical session endpoints.
class ListeningCoverageService {
  final AppDatabase db;

  ListeningCoverageService(this.db);

  Stream<BookListeningCoverage> watch(String bookId) =>
      Stream<BookListeningCoverage>.multi((output) {
        var cancelled = false;
        Future<void> pending = Future.value();
        void refresh() {
          pending = pending.then((_) async {
            if (cancelled) return;
            try {
              final coverage = await forBook(bookId);
              if (!cancelled) output.add(coverage);
            } catch (error, stack) {
              if (!cancelled) output.addError(error, stack);
            }
          });
        }

        // Subscribe before the initial read so a concurrent write cannot be
        // missed. Real table updates also cover duration/metadata changes.
        final subscription = db
            .tableUpdates(
              TableUpdateQuery.onAllTables([
                db.books,
                db.bookTracks,
                db.chapters,
                db.playbackCoverage,
              ]),
            )
            .listen(
              (_) => refresh(),
              onError: output.addError,
              onDone: () {
                cancelled = true;
                output.close();
              },
            );
        output.onCancel = () async {
          cancelled = true;
          await subscription.cancel();
        };
        refresh();
      });

  Future<BookListeningCoverage> forBook(String bookId) =>
      db.transaction(() async {
        final tracks = await db.tracksFor(bookId);
        final ranges = await db.coverageFor(bookId);
        final chapters = await db.chaptersFor(bookId);
        final byPath = <String, List<CoverageRange>>{};
        for (final range in ranges) {
          byPath.putIfAbsent(range.filePath, () => []).add(range);
        }
        final coverage = <TrackListeningCoverage>[];
        for (final track in tracks) {
          final duration = track.durationMs;
          final played = <CoverageInterval>[];
          for (final range in byPath[track.filePath] ?? <CoverageRange>[]) {
            final start = math.max(0, range.startMs);
            final end = duration == null
                ? range.endMs
                : math.min(range.endMs, duration);
            if (end <= start) continue;
            if (played.isNotEmpty && start <= played.last.endMs) {
              played[played.length - 1] = CoverageInterval(
                startMs: played.last.startMs,
                endMs: math.max(played.last.endMs, end),
              );
            } else {
              played.add(CoverageInterval(startMs: start, endMs: end));
            }
          }
          final gaps = <CoverageInterval>[];
          if (duration != null) {
            var cursor = 0;
            for (final interval in played) {
              if (cursor < interval.startMs) {
                gaps.add(
                  CoverageInterval(startMs: cursor, endMs: interval.startMs),
                );
              }
              cursor = interval.endMs;
            }
            if (cursor < duration) {
              gaps.add(CoverageInterval(startMs: cursor, endMs: duration));
            }
          }
          final sourceChapters = chapters.where(
            (chapter) =>
                chapter.filePath == track.filePath ||
                (chapter.filePath == null &&
                    chapter.trackIndex == track.trackIndex),
          );
          final filename = p
              .basenameWithoutExtension(track.filePath)
              .replaceFirst(RegExp(r'^\d{5}_'), '');
          final title =
              sourceChapters.length == 1 &&
                  sourceChapters.single.title.trim().isNotEmpty
              ? sourceChapters.single.title
              : filename.isNotEmpty
              ? filename
              : 'Part ${track.trackIndex + 1}';
          coverage.add(
            TrackListeningCoverage(
              filePath: track.filePath,
              trackIndex: track.trackIndex,
              title: title,
              durationMs: duration,
              played: played,
              gaps: gaps,
            ),
          );
        }
        return BookListeningCoverage(bookId: bookId, tracks: coverage);
      });
}
