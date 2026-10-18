import 'dart:async';
import 'package:flutter/material.dart';
import '../services/audio/playback_service.dart';

class VolumeControlButton extends StatelessWidget {
  final PlaybackService playback;
  final double volume;
  const VolumeControlButton({
    super.key,
    required this.playback,
    required this.volume,
  });
  @override
  Widget build(BuildContext context) => Tooltip(
    message: 'Playback volume',
    child: Semantics(
      label: 'Playback volume',
      child: TextButton.icon(
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => _VolumeSheet(playback: playback),
        ),
        icon: Icon(volume == 0 ? Icons.volume_off : Icons.volume_up, size: 20),
        label: Text('${(volume * 100).round()}%'),
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
    ),
  );
}

class _VolumeSheet extends StatefulWidget {
  final PlaybackService playback;
  const _VolumeSheet({required this.playback});
  @override
  State<_VolumeSheet> createState() => _VolumeSheetState();
}

class _VolumeSheetState extends State<_VolumeSheet> {
  double previous = 1;
  late final StreamSubscription _subscription;
  @override
  void initState() {
    super.initState();
    previous = widget.playback.state.volume > 0
        ? widget.playback.state.volume
        : (widget.playback.settings?.unmutedVolume ?? 1);
    _subscription = widget.playback.stateStream.listen((state) {
      if (state.volume > 0) previous = state.volume;
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  Future<void> change(double value) async {
    final volume = value.clamp(0.0, 1.0);
    if (volume > 0) previous = volume;
    try {
      await widget.playback.setVolume(volume);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Volume could not be changed: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final volume = widget.playback.state.volume;
    final percent = (volume * 100).round();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Playback volume',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              '$percent%',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            Slider(
              key: const ValueKey('playback-volume-slider'),
              value: volume,
              min: 0,
              max: 1,
              divisions: 100,
              label: '$percent%',
              semanticFormatterCallback: (value) =>
                  'Playback volume ${(value * 100).round()} percent',
              onChanged: change,
            ),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Decrease volume by 5 percent',
                  onPressed: volume > 0 ? () => change(volume - .05) : null,
                  icon: const Icon(Icons.remove),
                ),
                OutlinedButton.icon(
                  onPressed: () => change(volume == 0 ? previous : 0),
                  icon: Icon(volume == 0 ? Icons.volume_up : Icons.volume_off),
                  label: Text(volume == 0 ? 'Unmute' : 'Mute'),
                ),
                IconButton(
                  tooltip: 'Increase volume by 5 percent',
                  onPressed: volume < 1 ? () => change(volume + .05) : null,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Controls this app’s audio level. Your device volume also affects loudness.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}
