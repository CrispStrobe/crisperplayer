/// A conservative trace of decoder progress, never an inference from the
/// endpoints of a listening session. The owner resets it before every seek.
class PlayedRangeRecorder {
  _PositionSample? _previous;
  final List<RecordedRange> _pending = [];

  void reset() => _previous = null;

  void sample({
    required String bookId,
    required String filePath,
    required int positionMs,
    required int observedAtMs,
    required double speed,
  }) {
    final previous = _previous;
    _previous = _PositionSample(bookId, filePath, positionMs, observedAtMs);
    if (previous == null ||
        previous.bookId != bookId ||
        previous.filePath != filePath ||
        positionMs <= previous.positionMs) {
      return;
    }
    final elapsed = observedAtMs - previous.observedAtMs;
    final advanced = positionMs - previous.positionMs;
    // A decoder discontinuity or a clock moving backwards cannot prove that
    // the intervening audio played. Allow normal position callback jitter.
    if (elapsed < 0 || advanced > elapsed * speed + 1500) return;
    final range = RecordedRange(
      bookId: bookId,
      filePath: filePath,
      startMs: previous.positionMs,
      endMs: positionMs,
      heardAtMs: observedAtMs,
    );
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
          heardAtMs: observedAtMs,
        );
        return;
      }
    }
    // Normal playback checkpoints every two seconds. Bound memory even if
    // persistent storage is unavailable for an extended period.
    if (_pending.length == 200) _pending.removeAt(0);
    _pending.add(range);
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
  final int heardAtMs;

  const RecordedRange({
    required this.bookId,
    required this.filePath,
    required this.startMs,
    required this.endMs,
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
