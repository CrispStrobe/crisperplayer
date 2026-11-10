import 'package:uuid/uuid.dart';

import 'played_range_recorder.dart';

/// Checkpointable continuous passages. A stable ID is extended while physical
/// playback, clock samples, speed and UTC offset stay contiguous. Replays,
/// pauses and seeks create new entries, even at the same source position.
class ListeningJournalRecorder {
  JournalPassage? _active;
  final Map<String, JournalPassage> _pending = {};

  void reset() => _active = null;

  void record(
    RecordedRange observed, {
    required double speed,
    required int utcOffsetMinutes,
    String? chapterTitle,
    String? reason,
  }) {
    final previous = _active;
    final continuous =
        previous != null &&
        previous.bookId == observed.bookId &&
        previous.filePath == observed.filePath &&
        previous.endMs == observed.startMs &&
        previous.endedAtMs == observed.startedAtMs &&
        previous.speed == speed &&
        previous.utcOffsetMinutes == utcOffsetMinutes &&
        previous.chapterTitle == chapterTitle &&
        previous.reason == reason;
    final passage = JournalPassage(
      id: continuous ? previous.id : const Uuid().v4(),
      bookId: observed.bookId,
      filePath: observed.filePath,
      startMs: continuous ? previous.startMs : observed.startMs,
      endMs: observed.endMs,
      startedAtMs: continuous ? previous.startedAtMs : observed.startedAtMs,
      endedAtMs: observed.heardAtMs,
      utcOffsetMinutes: utcOffsetMinutes,
      speed: speed,
      chapterTitle: chapterTitle,
      reason: reason,
    );
    _active = passage;
    _pending[passage.id] = passage;
  }

  List<JournalPassage> get pending => List.unmodifiable(_pending.values);

  /// A callback can extend a passage during an asynchronous database write.
  /// Acknowledge only that exact snapshot; a newer version stays pending.
  void acknowledge(JournalPassage passage) {
    if (identical(_pending[passage.id], passage)) {
      _pending.remove(passage.id);
    }
  }

  void clear({String? bookId}) {
    if (bookId == null) {
      _pending.clear();
      _active = null;
    } else {
      _pending.removeWhere((_, entry) => entry.bookId == bookId);
      if (_active?.bookId == bookId) _active = null;
    }
  }
}

class JournalPassage {
  final String id;
  final String bookId;
  final String filePath;
  final int startMs;
  final int endMs;
  final int startedAtMs;
  final int endedAtMs;
  final int utcOffsetMinutes;
  final double speed;
  final String? chapterTitle;
  final String? reason;

  const JournalPassage({
    required this.id,
    required this.bookId,
    required this.filePath,
    required this.startMs,
    required this.endMs,
    required this.startedAtMs,
    required this.endedAtMs,
    required this.utcOffsetMinutes,
    required this.speed,
    this.chapterTitle,
    this.reason,
  });
}
