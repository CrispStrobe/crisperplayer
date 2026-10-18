import 'db/app_database.dart';

/// Actual listening time from session checkpoints, independent of playback speed.
Map<String, Object> listeningStats(
  List<ListeningHistoryData> entries, {
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  final today = DateTime(clock.year, clock.month, clock.day);
  final week = DateTime(clock.year, clock.month, clock.day - 6);
  int since(DateTime boundary) {
    var total = 0;
    for (final e in entries) {
      final start = e.startedAtMs;
      final end = e.endedAtMs ?? (start + e.listenedMs);
      final span = end - start;
      if (span <= 0 || e.listenedMs <= 0) continue;
      final lo = start > boundary.millisecondsSinceEpoch
          ? start
          : boundary.millisecondsSinceEpoch;
      final hi = end < clock.millisecondsSinceEpoch
          ? end
          : clock.millisecondsSinceEpoch;
      if (hi > lo) total += (e.listenedMs * (hi - lo) / span).round();
    }
    return total;
  }

  return {
    'todayMs': since(today),
    'weekMs': since(week),
    'totalMs': entries.fold<int>(0, (sum, e) => sum + e.listenedMs),
    'sessions': entries.length,
    'books': entries.map((e) => e.bookId).toSet().length,
  };
}
