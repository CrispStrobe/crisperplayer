import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import '../services/audio/waveform_service.dart';
import 'waveform_view.dart';

class AudioWaveformPanel extends StatefulWidget {
  final String? path;
  final Duration duration, position;
  final ValueChanged<Duration> onSeek;
  final bool visible;
  final ValueChanged<bool> onVisibilityChanged;
  final WaveformService? service;
  const AudioWaveformPanel({
    super.key,
    required this.path,
    required this.duration,
    required this.position,
    required this.onSeek,
    required this.visible,
    required this.onVisibilityChanged,
    this.service,
  });
  @override
  State<AudioWaveformPanel> createState() => _AudioWaveformPanelState();
}

class _AudioWaveformPanelState extends State<AudioWaveformPanel> {
  WaveformService get service => widget.service ?? WaveformService.shared;
  AudioWaveform? waveform;
  bool working = false;
  double progress = 0;
  String? error;
  int generation = 0;
  @override
  void initState() {
    super.initState();
    service.addListener(reloadCache);
    load();
  }

  @override
  void didUpdateWidget(AudioWaveformPanel old) {
    super.didUpdateWidget(old);
    if (old.service != widget.service) {
      (old.service ?? WaveformService.shared).removeListener(reloadCache);
      service.addListener(reloadCache);
    }
    if (old.path != widget.path || old.service != widget.service) load();
  }

  @override
  void dispose() {
    service.removeListener(reloadCache);
    super.dispose();
  }

  Future<void> reloadCache() async {
    final path = widget.path, token = generation;
    if (path == null) return;
    try {
      final cached = await service.cached(path);
      if (mounted && generation == token && cached != null) {
        setState(() => waveform = cached);
      }
    } catch (_) {
      /* Regeneration errors are reported by Generate. */
    }
  }

  Future<void> load() async {
    final token = ++generation, path = widget.path;
    waveform = null;
    error = null;
    working = false;
    progress = 0;
    if (path == null) return;
    try {
      final cached = await service.cached(path);
      if (mounted && generation == token) setState(() => waveform = cached);
    } catch (_) {
      /* Missing cache/source does not affect playback. Generate reports errors. */
    }
  }

  Future<void> generate() async {
    final path = widget.path;
    if (path == null || working) return;
    final token = generation;
    setState(() {
      working = true;
      error = null;
      progress = 0;
    });
    try {
      final result = await service.generate(
        path,
        widget.duration,
        onProgress: (value) {
          if (mounted &&
              generation == token &&
              (value * 100).floor() != (progress * 100).floor()) {
            setState(() => progress = value);
          }
        },
      );
      if (mounted && generation == token) setState(() => waveform = result);
    } catch (e) {
      if (mounted && generation == token) {
        setState(
          () => error =
              'Waveform unavailable: ${e is FileSystemException
                  ? e.message
                  : e is FormatException
                  ? e.message
                  : e is PlatformException
                  ? (e.message ?? 'The audio decoder could not read this track.')
                  : 'Audio analysis failed. Playback remains available.'}',
        );
      }
    } finally {
      if (mounted && generation == token) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const Expanded(child: Text('Audio waveform · current track')),
          IconButton(
            tooltip: widget.visible
                ? 'Hide audio waveform'
                : 'Show audio waveform',
            onPressed: () => widget.onVisibilityChanged(!widget.visible),
            icon: Icon(
              widget.visible ? Icons.visibility_off_outlined : Icons.graphic_eq,
            ),
          ),
        ],
      ),
      if (widget.visible) ...[
        if (waveform != null)
          ExcludeSemantics(
            child: WaveformView(
              peaks: waveform!.peaks,
              position: widget.position,
              duration: waveform!.duration,
              height: 56,
              onSeek: widget.onSeek,
            ),
          )
        else if (working) ...[
          LinearProgressIndicator(value: progress > 0 ? progress : null),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Analyzing audio locally… ${(progress * 100).floor()}%',
            ),
          ),
        ] else ...[
          OutlinedButton.icon(
            onPressed: widget.path == null ? null : generate,
            icon: const Icon(Icons.graphic_eq),
            label: const Text('Generate audio waveform'),
          ),
          const Text(
            'Measured from this track, on device. Long files may take time.',
            style: TextStyle(fontSize: 12),
          ),
        ],
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ],
  );
}
