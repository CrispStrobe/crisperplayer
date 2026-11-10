/// A half-open interval in a physical audio file, measured in media time.
class CoverageInterval {
  final int startMs;
  final int endMs;

  const CoverageInterval({required this.startMs, required this.endMs});

  int get lengthMs => endMs - startMs;

  Map<String, int> toJson() => {'startMs': startMs, 'endMs': endMs};
}

/// Unique confirmed playback for one current physical track.
/// Unknown durations have no inferred gaps or completion percentage.
class TrackListeningCoverage {
  final String filePath;
  final int trackIndex;
  final String title;
  final int? durationMs;
  final List<CoverageInterval> played;
  final List<CoverageInterval> gaps;

  TrackListeningCoverage({
    required this.filePath,
    required this.trackIndex,
    required this.title,
    required this.durationMs,
    required List<CoverageInterval> played,
    required List<CoverageInterval> gaps,
  }) : played = List.unmodifiable(played),
       gaps = List.unmodifiable(gaps);

  int get playedMs =>
      played.fold(0, (sum, interval) => sum + interval.lengthMs);

  int get timelineExtentMs =>
      durationMs ?? (played.isEmpty ? 0 : played.last.endMs);

  double? get fraction => durationMs == null
      ? null
      : durationMs == 0
      ? 0
      : (playedMs / durationMs!).clamp(0.0, 1.0);

  Map<String, Object?> toJson() => {
    'filePath': filePath,
    'trackIndex': trackIndex,
    'title': title,
    'durationMs': durationMs,
    'playedMs': playedMs,
    'timelineExtentMs': timelineExtentMs,
    'fraction': fraction,
    'played': played.map((interval) => interval.toJson()).toList(),
    'gaps': gaps.map((interval) => interval.toJson()).toList(),
  };
}

/// Coverage is the union of recorded intervals, independent of resume position,
/// playback speed, replays and the bounded recent Return Trail list.
class BookListeningCoverage {
  final String bookId;
  final List<TrackListeningCoverage> tracks;

  BookListeningCoverage({
    required this.bookId,
    required List<TrackListeningCoverage> tracks,
  }) : tracks = List.unmodifiable(tracks);

  int get playedMs => tracks.fold(0, (sum, track) => sum + track.playedMs);

  int? get durationMs =>
      tracks.isEmpty || tracks.any((track) => track.durationMs == null)
      ? null
      : tracks.fold<int>(0, (sum, track) => sum + track.durationMs!);

  double? get fraction {
    final duration = durationMs;
    if (duration == null) return null;
    return duration == 0 ? 0 : (playedMs / duration).clamp(0.0, 1.0);
  }

  Map<String, Object?> toJson() => {
    'bookId': bookId,
    'playedMs': playedMs,
    'durationMs': durationMs,
    'fraction': fraction,
    'tracks': tracks.map((track) => track.toJson()).toList(),
  };
}
