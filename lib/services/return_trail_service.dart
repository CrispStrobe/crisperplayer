import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../models/return_trail.dart';
import 'db/app_database.dart';

/// Records demonstrated playback ranges and builds bounded replays from them.
/// This service never infers that the interval between two seeks was heard.
class ReturnTrailService {
  final AppDatabase db;
  static const _minimumClipMs = 2000;

  ReturnTrailService(this.db);

  /// The coordinator supplies continuous, playing-only intervals. Separate
  /// intervals merge only when they actually overlap or touch, without gaps.
  Future<void> record({
    required String bookId,
    required String filePath,
    required int startMs,
    required int endMs,
    required int heardAtMs,
  }) async {
    if (bookId.isEmpty ||
        filePath.isEmpty ||
        startMs < 0 ||
        endMs <= startMs ||
        heardAtMs < 0) {
      throw ArgumentError('A valid played passage is required');
    }
    await db.transaction(() async {
      final previous =
          await (db.select(db.playedPassages)
                ..where(
                  (p) => p.bookId.equals(bookId) & p.filePath.equals(filePath),
                )
                ..orderBy([
                  (p) => OrderingTerm.desc(p.heardAtMs),
                  (p) => OrderingTerm.desc(p.id),
                ])
                ..limit(1))
              .getSingleOrNull();
      if (previous != null &&
          heardAtMs >= previous.heardAtMs &&
          heardAtMs - previous.heardAtMs <= 10000 &&
          startMs <= previous.endMs &&
          endMs >= previous.startMs) {
        await (db.update(
          db.playedPassages,
        )..where((p) => p.id.equals(previous.id))).write(
          PlayedPassagesCompanion(
            startMs: Value(math.min(previous.startMs, startMs)),
            endMs: Value(math.max(previous.endMs, endMs)),
            heardAtMs: Value(heardAtMs),
          ),
        );
      } else {
        await db
            .into(db.playedPassages)
            .insert(
              PlayedPassagesCompanion.insert(
                bookId: bookId,
                filePath: filePath,
                startMs: startMs,
                endMs: endMs,
                heardAtMs: heardAtMs,
              ),
            );
      }
      await db.prunePlayedPassages(bookId);
    });
  }

  Future<void> clearForBook(String bookId) => (db.delete(
    db.playedPassages,
  )..where((p) => p.bookId.equals(bookId))).go();

  /// [budget] is listening time at [speed]. All excerpts remain at or before
  /// [anchor], even if the listener previously visited later parts of the book.
  Future<ReturnTrailPlan> plan({
    required TrailAnchor anchor,
    Duration budget = const Duration(seconds: 60),
    double speed = 1,
  }) async {
    if (budget < const Duration(seconds: 15) ||
        budget > const Duration(minutes: 5)) {
      throw ArgumentError.value(budget, 'budget', 'Choose 15 to 300 seconds');
    }
    if (!speed.isFinite || speed < 0.5 || speed > 3) {
      throw ArgumentError.value(speed, 'speed', 'Choose a speed from 0.5 to 3');
    }
    if (anchor.bookId.isEmpty ||
        anchor.filePath.isEmpty ||
        anchor.positionMs < 0) {
      throw ArgumentError('A valid return place is required');
    }
    final tracks = await db.tracksFor(anchor.bookId);
    final anchorIndex = tracks.indexWhere((t) => t.filePath == anchor.filePath);
    final clips = <TrailClip>[];
    ReturnTrailPlan result() => ReturnTrailPlan(
      anchor: anchor,
      clips: clips,
      requestedDuration: budget,
      playbackSpeed: speed,
    );
    if (anchorIndex < 0) return result();

    final byPath = {for (final track in tracks) track.filePath: track};
    final passages = await db.playedPassagesFor(anchor.bookId);
    final candidates = <_Passage>[];
    final covered = <String, List<({int start, int end})>>{};
    // Newest first. Subtract newer coverage rather than replaying overlapping
    // ranges twice when a listener has already revisited a passage.
    for (final passage in passages) {
      final track = byPath[passage.filePath];
      if (track == null || track.trackIndex > tracks[anchorIndex].trackIndex) {
        continue;
      }
      final start = math.max(0, passage.startMs);
      var end = passage.endMs;
      if (track.durationMs != null) end = math.min(end, track.durationMs!);
      if (passage.filePath == anchor.filePath) {
        end = math.min(end, anchor.positionMs);
      }
      if (end - start < _minimumClipMs) continue;
      var fragments = <({int start, int end})>[(start: start, end: end)];
      for (final existing in covered[passage.filePath] ?? []) {
        final remainder = <({int start, int end})>[];
        for (final fragment in fragments) {
          if (existing.end <= fragment.start ||
              existing.start >= fragment.end) {
            remainder.add(fragment);
          } else {
            if (fragment.start < existing.start) {
              remainder.add((start: fragment.start, end: existing.start));
            }
            if (fragment.end > existing.end) {
              remainder.add((start: existing.end, end: fragment.end));
            }
          }
        }
        fragments = remainder;
      }
      covered.putIfAbsent(passage.filePath, () => []).add((
        start: start,
        end: end,
      ));
      for (final fragment in fragments.reversed) {
        if (fragment.end - fragment.start < _minimumClipMs) continue;
        candidates.add(
          _Passage(
            track: track,
            startMs: fragment.start,
            endMs: fragment.end,
            heardAtMs: passage.heardAtMs,
            id: passage.id,
          ),
        );
        if (candidates.length == 3) break;
      }
      if (candidates.length == 3) break;
    }
    if (candidates.isEmpty) return result();

    final mediaBudget = (budget.inMilliseconds * speed).floor();
    final allocations = List<int>.filled(candidates.length, 0);
    if (candidates.length == 1) {
      allocations[0] = math.min(candidates[0].length, mediaBudget);
    } else {
      // Give the latest passage roughly half the available time, then share
      // the rest across earlier passages. Redistribute unused short segments.
      allocations[0] = math.min(
        candidates[0].length,
        math.min(
          (mediaBudget / 2).ceil(),
          mediaBudget - _minimumClipMs * (candidates.length - 1),
        ),
      );
      var remaining = mediaBudget - allocations[0];
      for (var i = 1; i < candidates.length; i++) {
        allocations[i] = math.min(
          candidates[i].length,
          math.max(_minimumClipMs, remaining ~/ (candidates.length - i)),
        );
        remaining -= allocations[i];
      }
      for (var i = 0; i < candidates.length && remaining > 0; i++) {
        final extra = math.min(
          candidates[i].length - allocations[i],
          remaining,
        );
        allocations[i] += extra;
        remaining -= extra;
      }
    }

    final chapters = await db.chaptersFor(anchor.bookId);
    final selected = <({TrailClip clip, _Passage passage})>[];
    for (var i = 0; i < candidates.length; i++) {
      final passage = candidates[i];
      if (allocations[i] <= 0) continue;
      final clipStart = passage.endMs - allocations[i];
      selected.add((
        clip: TrailClip(
          filePath: passage.track.filePath,
          trackIndex: passage.track.trackIndex,
          startMs: clipStart,
          endMs: passage.endMs,
          title: _title(passage.track, clipStart, tracks, chapters),
          reason: i == 0 ? 'Last played passage' : 'Earlier played passage',
        ),
        passage: passage,
      ));
    }
    // Recreate the order the passages were heard; ties have stable physical
    // ordering. Recency determines selection, never a fabricated summary.
    selected.sort((a, b) {
      var order = a.passage.heardAtMs.compareTo(b.passage.heardAtMs);
      if (order == 0) order = a.passage.id.compareTo(b.passage.id);
      if (order == 0) order = a.clip.trackIndex.compareTo(b.clip.trackIndex);
      if (order == 0) order = a.clip.startMs.compareTo(b.clip.startMs);
      return order;
    });
    clips.addAll(selected.map((entry) => entry.clip));
    return result();
  }

  String _title(
    BookTrack track,
    int startMs,
    List<BookTrack> tracks,
    List<Chapter> chapters,
  ) {
    final preceding = tracks.where((t) => t.trackIndex < track.trackIndex);
    final trackChapters = chapters.where(
      (c) =>
          c.filePath == track.filePath ||
          (c.filePath == null && c.trackIndex == track.trackIndex),
    );
    if (preceding.every((t) => t.durationMs != null)) {
      final bookStart =
          preceding.fold(0, (sum, t) => sum + t.durationMs!) + startMs;
      for (final chapter in trackChapters) {
        if (chapter.startMs <= bookStart &&
            bookStart < chapter.endMs &&
            chapter.title.trim().isNotEmpty) {
          return chapter.title;
        }
      }
    } else if (trackChapters.length == 1 &&
        trackChapters.single.title.trim().isNotEmpty) {
      return trackChapters.single.title;
    }
    return 'Part ${track.trackIndex + 1}';
  }
}

class _Passage {
  final BookTrack track;
  final int startMs;
  final int endMs;
  final int heardAtMs;
  final int id;

  const _Passage({
    required this.track,
    required this.startMs,
    required this.endMs,
    required this.heardAtMs,
    required this.id,
  });

  int get length => endMs - startMs;
}
