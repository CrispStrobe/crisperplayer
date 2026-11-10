/// A saved place in the original audio. File-local offsets remain meaningful
/// even when another track's duration is unknown.
class TrailAnchor {
  final String bookId;
  final String filePath;
  final int positionMs;

  const TrailAnchor({
    required this.bookId,
    required this.filePath,
    required this.positionMs,
  });

  Map<String, Object> toJson() => {
    'bookId': bookId,
    'filePath': filePath,
    'positionMs': positionMs,
  };
}

/// An excerpt entirely contained in a passage recorded during playback.
/// Titles come from chapter metadata, never from an inferred summary.
class TrailClip {
  final String filePath;
  final int trackIndex;
  final int startMs;
  final int endMs;
  final String title;
  final String reason;

  const TrailClip({
    required this.filePath,
    required this.trackIndex,
    required this.startMs,
    required this.endMs,
    required this.title,
    required this.reason,
  });

  Duration get duration => Duration(milliseconds: endMs - startMs);

  Map<String, Object> toJson() => {
    'filePath': filePath,
    'trackIndex': trackIndex,
    'startMs': startMs,
    'endMs': endMs,
    'title': title,
    'reason': reason,
    'durationMs': duration.inMilliseconds,
  };
}

/// An explainable, local replay plan with an independent protected place.
class ReturnTrailPlan {
  final TrailAnchor anchor;
  final List<TrailClip> clips;
  final Duration requestedDuration;
  final double playbackSpeed;

  ReturnTrailPlan({
    required this.anchor,
    required List<TrailClip> clips,
    required this.requestedDuration,
    required this.playbackSpeed,
  }) : clips = List.unmodifiable(clips);

  String get bookId => anchor.bookId;

  Duration get mediaDuration => Duration(
    milliseconds: clips.fold(
      0,
      (sum, clip) => sum + clip.duration.inMilliseconds,
    ),
  );

  Duration get estimatedDuration => Duration(
    milliseconds: (mediaDuration.inMilliseconds / playbackSpeed).ceil(),
  );

  Map<String, Object> toJson() => {
    'bookId': bookId,
    'anchor': anchor.toJson(),
    'clips': clips.map((clip) => clip.toJson()).toList(),
    'requestedDurationMs': requestedDuration.inMilliseconds,
    'mediaDurationMs': mediaDuration.inMilliseconds,
    'estimatedDurationMs': estimatedDuration.inMilliseconds,
    'playbackSpeed': playbackSpeed,
  };
}
