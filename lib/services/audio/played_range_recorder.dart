/// A conservative trace of decoder progress, never an inference from the
/// endpoints of a listening session. The owner resets it before every seek.
class PlayedRangeRecorder {
  final bool retainPending;
  PlayedRangeRecorder({this.retainPending = true});

  _PositionSample? _previous;
  final List<RecordedRange> _pending = [];

  void reset() => _previous = null;

  void clear() {
    _previous = null;
    _pending.clear();
  }

  /// Returns only the newly observed pair. Consumers that need timestamps can
  /// retain this independently of the bounded recent-passage queue.
  RecordedRange? sample({
    required String bookId,
    required String filePath,
    required int positionMs,
    required int observedAtMs,
    required double speed,
  }) {
    final previous = _previous;
    // A checkpoint can read the same decoder position between callbacks. Keep
    // the earlier observation so it does not split a continuous dated passage.
    if (previous != null &&
        previous.bookId == bookId &&
        previous.filePath == filePath &&
        previous.positionMs == positionMs &&
        observedAtMs >= previous.observedAtMs) {
      return null;
    }
    _previous = _PositionSample(bookId, filePath, positionMs, observedAtMs);
    if (previous == null ||
        previous.bookId != bookId ||
        previous.filePath != filePath ||
        positionMs <= previous.positionMs) {
      return null;
    }
    final elapsed = observedAtMs - previous.observedAtMs;
    final advanced = positionMs - previous.positionMs;
    // A decoder discontinuity or a clock moving backwards cannot prove that
    // the intervening audio played. Allow normal position callback jitter.
    if (elapsed < 0 || advanced > elapsed * speed + 1500) return null;
    final range = RecordedRange(
      bookId: bookId,
      filePath: filePath,
      startMs: previous.positionMs,
      endMs: positionMs,
      startedAtMs: previous.observedAtMs,
      heardAtMs: observedAtMs,
    );
    if (!retainPending) return range;
    if (_pending.isNotEmpty) {
      final last = _pending.last;
      if (last.bookId == bookId &&
          last.filePath == filePath &&
          last.endMs == range.startMs) {
        _pending[_pending.length - 1] = RecordedRange(
          bookId: bookId,
          filePath: filePath,
          startMs: last.startMs,
          endMs: range.endMs,
          startedAtMs: last.startedAtMs,
          heardAtMs: observedAtMs,
        );
        return range;
      }
    }
    // Normal playback checkpoints every two seconds. Bound memory even if
    // persistent storage is unavailable for an extended period.
    if (_pending.length == 200) _pending.removeAt(0);
    _pending.add(range);
    return range;
  }

  List<RecordedRange> get pending => List.unmodifiable(_pending);

  /// Remove only the object actually saved; later samples may have extended it.
  void acknowledge(RecordedRange range) {
    final index = _pending.indexOf(range);
    if (index >= 0) _pending.removeAt(index);
  }
}

class RecordedRange {
  final String bookId;
  final String filePath;
  final int startMs;
  final int endMs;
  final int startedAtMs;
  final int heardAtMs;

  const RecordedRange({
    required this.bookId,
    required this.filePath,
    required this.startMs,
    required this.endMs,
    required this.startedAtMs,
    required this.heardAtMs,
  });
}

class _PositionSample {
  final String bookId;
  final String filePath;
  final int positionMs;
  final int observedAtMs;
  const _PositionSample(
    this.bookId,
    this.filePath,
    this.positionMs,
    this.observedAtMs,
  );
}
