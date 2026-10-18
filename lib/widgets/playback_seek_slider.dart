import 'package:flutter/material.dart';
import '../utils/format.dart';

/// Continuous touch seeking, with predictable screen-reader skip increments.
class PlaybackSeekSlider extends StatelessWidget {
  final Duration position;
  final Duration duration;
  final Duration step;
  final ValueChanged<Duration> onSeek;
  const PlaybackSeekSlider({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.step = const Duration(seconds: 30),
  }) : assert(step > Duration.zero);

  @override
  Widget build(BuildContext context) {
    final total = duration.isNegative ? 0 : duration.inMilliseconds;
    final current = position.inMilliseconds.clamp(0, total);
    final next = (current + step.inMilliseconds).clamp(0, total);
    final previous = (current - step.inMilliseconds).clamp(0, total);
    String value(int milliseconds) =>
        '${formatSpokenDuration(Duration(milliseconds: milliseconds))} of ${formatSpokenDuration(duration)}';
    return Semantics(
      container: true,
      slider: true,
      enabled: total > 0,
      label: 'Playback position',
      value: total > 0 ? value(current) : 'Duration unavailable',
      increasedValue: current < total ? value(next) : null,
      decreasedValue: current > 0 ? value(previous) : null,
      onIncrease: current < total
          ? () => onSeek(Duration(milliseconds: next))
          : null,
      onDecrease: current > 0
          ? () => onSeek(Duration(milliseconds: previous))
          : null,
      child: ExcludeSemantics(
        child: Slider(
          min: 0,
          max: total > 0 ? total.toDouble() : 1,
          value: current.toDouble(),
          onChanged: total > 0
              ? (v) => onSeek(Duration(milliseconds: v.round()))
              : null,
        ),
      ),
    );
  }
}
