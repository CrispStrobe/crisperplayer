import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Static peaks measured from audio. Playback changes only the playhead/tint.
class WaveformView extends StatelessWidget {
  final bool isPlaying; // Kept for callers; never animates amplitude.
  final Duration position, duration;
  final List<double> peaks;
  final List<int> chapterEndFractions;
  final double height;
  final Color? color;
  final ValueChanged<Duration>? onSeek;
  const WaveformView({
    super.key,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.peaks = const [],
    this.chapterEndFractions = const [],
    this.height = 48,
    this.color,
    this.onSeek,
  });
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        void seek(Offset local) {
          if (duration <= Duration.zero || constraints.maxWidth <= 0) return;
          onSeek?.call(
            Duration(
              milliseconds:
                  (duration.inMilliseconds *
                          (local.dx / constraints.maxWidth).clamp(0, 1))
                      .round(),
            ),
          );
        }

        return GestureDetector(
          onTapDown: onSeek == null
              ? null
              : (event) => seek(event.localPosition),
          onHorizontalDragUpdate: onSeek == null
              ? null
              : (event) => seek(event.localPosition),
          child: SizedBox(
            width: double.infinity,
            height: height,
            child: CustomPaint(
              painter: _WaveformPainter(
                peaks,
                position,
                duration,
                color ?? colors.primary,
                colors.surfaceContainerHighest,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> peaks;
  final Duration position, duration;
  final Color color, inactive;
  _WaveformPainter(
    this.peaks,
    this.position,
    this.duration,
    this.color,
    this.inactive,
  );
  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final fraction = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final count = math.min(peaks.length, math.max(1, size.width ~/ 3));
    if (count == 0) {
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        Paint()
          ..color = inactive
          ..strokeWidth = 1,
      );
      return;
    }
    final width = size.width / count;
    for (var index = 0; index < count; index++) {
      var peak = 0.0;
      for (
        var sample = index * peaks.length ~/ count;
        sample < (index + 1) * peaks.length ~/ count;
        sample++
      ) {
        peak = math.max(peak, peaks[sample].clamp(0, 1));
      }
      final height = math.max(1.0, peak * size.height);
      canvas.drawRect(
        Rect.fromLTWH(
          index * width,
          (size.height - height) / 2,
          math.max(1.0, width - 1),
          height,
        ),
        Paint()..color = index / count < fraction ? color : inactive,
      );
    }
    final x = size.width * fraction;
    canvas.drawLine(
      Offset(x, 0),
      Offset(x, size.height),
      Paint()
        ..color = color
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.peaks != peaks ||
      old.position != position ||
      old.duration != duration ||
      old.color != color ||
      old.inactive != inactive;
}

/// Honest compact progress indicator; no fabricated audio amplitudes.
class MiniWaveform extends StatelessWidget {
  final double progress;
  final Color? color;
  const MiniWaveform({super.key, required this.progress, this.color});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 40,
    height: 14,
    child: Center(
      child: LinearProgressIndicator(
        value: progress.clamp(0, 1),
        color: color,
        minHeight: 3,
      ),
    ),
  );
}
