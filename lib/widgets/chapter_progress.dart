import 'package:flutter/material.dart';
import '../services/db/app_database.dart';
import 'playback_seek_slider.dart';

/// One accessible seek slider with chapter markers on its native track.
class ChapterProgressBar extends StatelessWidget {
  final Duration position;
  final Duration duration;
  final List<Chapter> chapters;
  final ValueChanged<Duration> onSeek;
  final Duration step;
  const ChapterProgressBar({
    super.key,
    required this.position,
    required this.duration,
    required this.chapters,
    required this.onSeek,
    this.step = const Duration(seconds: 30),
  });

  @override
  Widget build(BuildContext context) {
    final total = duration.inMilliseconds;
    return SliderTheme(
      data: SliderTheme.of(
        context,
      ).copyWith(trackHeight: 4, trackShape: _ChapterTrack(chapters, total)),
      child: PlaybackSeekSlider(
        position: position,
        duration: duration,
        step: step,
        onSeek: onSeek,
      ),
    );
  }
}

class _ChapterTrack extends RoundedRectSliderTrackShape {
  final List<Chapter> chapters;
  final int total;
  const _ChapterTrack(this.chapters, this.total);

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      textDirection: textDirection,
      thumbCenter: thumbCenter,
      secondaryOffset: secondaryOffset,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
      additionalActiveTrackHeight: additionalActiveTrackHeight,
    );
    if (total <= 0) return;
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final paint = Paint()
      ..color = sliderTheme.thumbColor ?? Colors.white
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final chapter in chapters) {
      final fraction = chapter.startMs / total;
      if (fraction <= 0 || fraction >= 1) continue;
      final x =
          rect.left +
          rect.width *
              (textDirection == TextDirection.rtl ? 1 - fraction : fraction);
      if ((x - thumbCenter.dx).abs() < 10) continue;
      context.canvas.drawLine(
        Offset(x, rect.center.dy - 5),
        Offset(x, rect.center.dy + 5),
        paint,
      );
    }
  }
}
