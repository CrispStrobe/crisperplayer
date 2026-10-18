import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Decorative waveform: synthetic bars animated when playing.
/// Not tied to real PCM — cosmetic polish, deterministic via seed.
class WaveformView extends StatefulWidget {
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final List<int> chapterEndFractions; // 0..1000 for markers if wanted
  final double height;
  final Color? color;

  const WaveformView({
    super.key,
    required this.isPlaying,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.chapterEndFractions = const [],
    this.height = 36,
    this.color,
  });

  @override
  State<WaveformView> createState() => _WaveformViewState();
}

class _WaveformViewState extends State<WaveformView>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    if (widget.isPlaying) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(covariant WaveformView old) {
    super.didUpdateWidget(old);
    if (widget.isPlaying && !_ctrl.isAnimating) {
      _ctrl.repeat();
    } else if (!widget.isPlaying && _ctrl.isAnimating) {
      _ctrl.stop();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final baseColor = widget.color ?? cs.primary;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (ctx, _) {
        return CustomPaint(
          size: Size(double.infinity, widget.height),
          painter: _WaveformPainter(
            anim: _ctrl.value,
            isPlaying: widget.isPlaying,
            position: widget.position,
            duration: widget.duration,
            chapterFractions: widget.chapterEndFractions,
            color: baseColor,
            inactiveColor: cs.surfaceContainerHighest,
          ),
        );
      },
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final double anim;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final List<int> chapterFractions;
  final Color color;
  final Color inactiveColor;

  _WaveformPainter({
    required this.anim,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.chapterFractions,
    required this.color,
    required this.inactiveColor,
  });

  static const int barCount = 48;
  // deterministic pseudo-random heights seeded per bar
  static List<double> _heights(int count) {
    final rng = math.Random(42);
    return List.generate(count, (_) => 0.25 + rng.nextDouble() * 0.75);
  }

  static final _cachedHeights = _heights(barCount);

  @override
  void paint(Canvas canvas, Size size) {
    final barW = size.width / barCount;
    final gap = barW * 0.25;
    final bw = barW - gap;
    final centerY = size.height / 2;

    final totalMs = duration.inMilliseconds;
    final posMs = position.inMilliseconds.clamp(0, totalMs > 0 ? totalMs : 1);
    final progress = totalMs == 0 ? 0 : posMs / totalMs;
    final progressX = size.width * progress;

    for (int i = 0; i < barCount; i++) {
      final baseH = _cachedHeights[i];
      // animate when playing: small wave modulation per bar phase
      double amp = baseH;
      if (isPlaying) {
        final phase = (anim * 2 * math.pi + i * 0.35);
        amp = (baseH * (0.85 + 0.3 * math.sin(phase))).clamp(0.15, 1.0);
      }
      final h = amp * size.height;
      final x = i * barW + gap / 2;
      final y = centerY - h / 2;

      final isPassed = x < progressX;
      final paint = Paint()
        ..color = (isPassed ? color : inactiveColor)
            .withValues(alpha: isPassed ? 0.95 : 0.9)
        ..style = PaintingStyle.fill;
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, bw.clamp(2, 10), h),
        Radius.circular(bw / 2),
      );
      canvas.drawRRect(rrect, paint);
    }

    // playhead line
    if (totalMs > 0) {
      canvas.drawLine(
        Offset(progressX, 0),
        Offset(progressX, size.height),
        Paint()
          ..color = color
          ..strokeWidth = 2,
      );
      canvas.drawCircle(Offset(progressX, centerY), 4, Paint()..color = color);
      canvas.drawCircle(
          Offset(progressX, centerY), 2, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.anim != anim ||
      old.position != position ||
      old.duration != duration ||
      old.isPlaying != isPlaying;
}

/// Compact inline waveform for mini player (static, no animation)
class MiniWaveform extends StatelessWidget {
  final double progress; // 0..1
  final Color? color;
  const MiniWaveform({super.key, required this.progress, this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CustomPaint(
      size: const Size(40, 14),
      painter: _MiniPainter(
          progress: progress,
          color: color ?? cs.primary,
          bg: cs.surfaceContainerHighest),
    );
  }
}

class _MiniPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color bg;
  _MiniPainter({required this.progress, required this.color, required this.bg});

  @override
  void paint(Canvas canvas, Size size) {
    final bars = 12;
    final rng = math.Random(7);
    final bw = size.width / bars;
    for (int i = 0; i < bars; i++) {
      final h = (0.3 + rng.nextDouble() * 0.7) * size.height;
      final x = i * bw + 1;
      final y = (size.height - h) / 2;
      final isActive = (i / bars) < progress;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, bw - 2, h), const Radius.circular(2)),
        Paint()..color = isActive ? color : bg,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MiniPainter old) => old.progress != progress;
}
