import 'package:flutter/material.dart';
import '../services/audio/playback_service.dart';

Future<void> showSpeedSheet(BuildContext context, PlaybackService svc) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (ctx) => _SpeedSheet(svc: svc),
  );
}

class _SpeedSheet extends StatefulWidget {
  final PlaybackService svc;
  const _SpeedSheet({required this.svc});
  @override
  State<_SpeedSheet> createState() => _SpeedSheetState();
}

class _SpeedSheetState extends State<_SpeedSheet> {
  late double _speed = widget.svc.state.speed;

  static const presets = [0.5, 0.8, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0];

  void _set(double v) {
    setState(() => _speed = v);
    widget.svc.setSpeed(v);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              Icon(Icons.speed, color: cs.primary),
              const SizedBox(width: 10),
              Text('Playback speed',
                  style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(20)),
                child: Text('${_speed.toStringAsFixed(2)}×',
                    style: TextStyle(
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.bold)),
              ),
            ]),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: presets.map((p) {
                final isSel = (_speed - p).abs() < 0.02;
                return ChoiceChip(
                  label:
                      Text('${p.toStringAsFixed(p.truncate() == p ? 1 : 2)}×'),
                  selected: isSel,
                  onSelected: (_) => _set(p),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Row(children: [
              const Icon(Icons.slow_motion_video, size: 18),
              Expanded(
                child: Slider(
                  min: 0.5,
                  max: 3.0,
                  divisions: 25,
                  label: '${_speed.toStringAsFixed(2)}×',
                  value: _speed.clamp(0.5, 3.0),
                  onChanged: (v) => setState(() => _speed = v),
                  onChangeEnd: _set,
                ),
              ),
              const Icon(Icons.fast_forward, size: 18),
            ]),
            Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text('0.5×', style: TextStyle(fontSize: 11)),
                  Text('3.0×', style: TextStyle(fontSize: 11)),
                ]),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done')),
          ],
        ),
      ),
    );
  }
}
