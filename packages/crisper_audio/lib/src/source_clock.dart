// SPDX-License-Identifier: MIT
import 'dart:collection';

class _Span {
  _Span(this.outputStart, this.outputEnd, this.sourceStart, this.sourceEnd);
  final int outputStart, outputEnd, sourceStart, sourceEnd;
}

/// Maps device-presented output frames back to the source represented by DSP.
/// Reads may run ahead, so cp_dsp_source_frames is recorded, not exposed directly.
class SourceClock {
  final Queue<_Span> _spans = Queue<_Span>();
  int _outputEnd = 0;
  int _sourceEnd = 0;
  int _anchorOutput = 0;
  int _anchorSource = 0;

  int get outputFrames => _outputEnd;
  int get pendingSpans => _spans.length;

  void reset() {
    _spans.clear();
    _outputEnd = _sourceEnd = _anchorOutput = _anchorSource = 0;
  }

  void append(int outputEnd, int sourceEnd) {
    if (outputEnd <= _outputEnd || sourceEnd < _sourceEnd) {
      throw StateError('Non-monotonic DSP source clock');
    }
    _spans.add(_Span(_outputEnd, outputEnd, _sourceEnd, sourceEnd));
    _outputEnd = outputEnd;
    _sourceEnd = sourceEnd;
  }

  int presented(int outputFrames) {
    if (outputFrames < _anchorOutput || outputFrames > _outputEnd) {
      throw StateError('Output clock outside submitted DSP history');
    }
    while (_spans.isNotEmpty && _spans.first.outputEnd <= outputFrames) {
      final span = _spans.removeFirst();
      _anchorOutput = span.outputEnd;
      _anchorSource = span.sourceEnd;
    }
    if (_spans.isEmpty) return _anchorSource;
    final span = _spans.first;
    return span.sourceStart +
        ((outputFrames - span.outputStart) *
                (span.sourceEnd - span.sourceStart)) ~/
            (span.outputEnd - span.outputStart);
  }
}
