import 'package:flutter/material.dart';
import '../services/db/app_database.dart';

/// Progress bar with chapter markers as vertical ticks.
/// Taps/drags seek via onSeek callback (0..1 fraction or Duration).
class ChapterProgressBar extends StatelessWidget {
  final Duration position;
  final Duration duration;
  final List<Chapter> chapters;
  final ValueChanged<Duration> onSeek;

  const ChapterProgressBar({
    super.key,
    required this.position,
    required this.duration,
    required this.chapters,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    final totalMs = duration.inMilliseconds;
    final posMs = position.inMilliseconds.clamp(0, totalMs > 0 ? totalMs : 1);
    final progress = totalMs == 0 ? 0.0 : posMs / totalMs;
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        // Custom slider area with markers
        LayoutBuilder(
          builder: (ctx, constraints) {
            final w = constraints.maxWidth;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) {
                final frac = (d.localPosition.dx / w).clamp(0.0, 1.0);
                onSeek(Duration(milliseconds: (frac * totalMs).round()));
              },
              onHorizontalDragUpdate: (d) {
                final frac = (d.localPosition.dx / w).clamp(0.0, 1.0);
                onSeek(Duration(milliseconds: (frac * totalMs).round()));
              },
              onHorizontalDragEnd: (_) {},
              child: SizedBox(
                height: 32,
                child: CustomPaint(
                  size: Size(w, 32),
                  painter: _ProgressPainter(
                    progress: progress,
                    chapters: chapters,
                    totalMs: totalMs,
                    activeColor: cs.primary,
                    inactiveColor: cs.surfaceContainerHighest,
                    markerColor: cs.onSurfaceVariant.withValues(alpha: 0.55),
                    playedMarkerColor: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ),
            );
          },
        ),
        // Fallback native Slider for accessibility + fine scrub
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
            activeTrackColor: cs.primary,
            inactiveTrackColor: cs.surfaceContainerHighest,
            thumbColor: cs.primary,
          ),
          child: Slider(
            min: 0,
            max: totalMs > 0 ? totalMs.toDouble() : 1,
            value: posMs.toDouble(),
            onChanged: (v) => onSeek(Duration(milliseconds: v.round())),
          ),
        ),
      ],
    );
  }
}

class _ProgressPainter extends CustomPainter {
  final double progress;
  final List<Chapter> chapters;
  final int totalMs;
  final Color activeColor;
  final Color inactiveColor;
  final Color markerColor;
  final Color playedMarkerColor;

  _ProgressPainter({
    required this.progress,
    required this.chapters,
    required this.totalMs,
    required this.activeColor,
    required this.inactiveColor,
    required this.markerColor,
    required this.playedMarkerColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final trackH = 6.0;
    final trackY = size.height / 2 - trackH / 2;
    final r = Radius.circular(trackH / 2);

    // background track
    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, trackY, size.width, trackH),
      r,
    );
    canvas.drawRRect(bgRect, Paint()..color = inactiveColor);

    // played portion
    if (progress > 0) {
      final playedRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, trackY, size.width * progress, trackH),
        r,
      );
      canvas.drawRRect(playedRect, Paint()..color = activeColor);
    }

    // chapter markers as vertical ticks
    if (chapters.isNotEmpty && totalMs > 0) {
      for (final ch in chapters) {
        // skip first chapter at 0
        if (ch.startMs == 0) continue;
        final frac = ch.startMs / totalMs;
        if (frac <= 0 || frac >= 1) continue;
        final x = frac * size.width;
        final isPlayed = frac <= progress;
        final paint = Paint()
          ..color = isPlayed ? playedMarkerColor : markerColor
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;
        // tick spanning track + a bit above/below
        canvas.drawLine(
            Offset(x, trackY - 5), Offset(x, trackY + trackH + 5), paint);
        // small dot at top for visibility
        canvas.drawCircle(
            Offset(x, trackY - 5), 2, Paint()..color = paint.color);
      }
    }

    // thumb circle at progress
    final thumbX = size.width * progress;
    canvas.drawCircle(
        Offset(thumbX, size.height / 2), 7, Paint()..color = activeColor);
    canvas.drawCircle(
        Offset(thumbX, size.height / 2), 3.5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant _ProgressPainter old) =>
      old.progress != progress ||
      old.chapters != chapters ||
      old.totalMs != totalMs;
}
