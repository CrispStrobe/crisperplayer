import 'dart:async';

import 'package:flutter/material.dart';

import '../models/playback_state.dart';
import '../services/audio/playback_service.dart';
import '../services/audio/speed_processing.dart';
import '../utils/format.dart';

Future<void> showSpeedSheet(BuildContext context, PlaybackService svc) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SpeedSheet(svc: svc),
    );

class _SpeedSheet extends StatefulWidget {
  final PlaybackService svc;
  const _SpeedSheet({required this.svc});

  @override
  State<_SpeedSheet> createState() => _SpeedSheetState();
}

class _SpeedSheetState extends State<_SpeedSheet> {
  static const presets = [0.5, 0.8, 1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0];
  final _form = GlobalKey<FormState>();
  final _inputFocus = FocusNode();
  late final TextEditingController _input;
  late final StreamSubscription<PlaybackState> _subscription;
  late final String? _bookId;
  late double _speed;
  bool _busy = false;
  bool _dragging = false;
  String? _error;

  bool get _bookChanged => widget.svc.currentBookId != _bookId;

  @override
  void initState() {
    super.initState();
    _bookId = widget.svc.currentBookId;
    _speed = widget.svc.state.speed;
    _input = TextEditingController(text: _speed.toStringAsFixed(2));
    _subscription = widget.svc.stateStream.listen((_) {
      if (!mounted) return;
      setState(() {
        if (!_dragging && !_busy) {
          _speed = widget.svc.state.speed;
          if (!_inputFocus.hasFocus) _input.text = _speed.toStringAsFixed(2);
        }
      });
    });
    widget.svc.settings?.addListener(_settingsChanged);
  }

  void _settingsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.svc.settings?.removeListener(_settingsChanged);
    _subscription.cancel();
    _input.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _set(double value) async {
    if (_busy || _bookChanged) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _dragging = false;
      _error = null;
    });
    try {
      await widget.svc.setSpeed(value, expectedBookId: _bookId);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Speed could not be changed: $error');
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _speed = widget.svc.state.speed;
          _input.text = _speed.toStringAsFixed(2);
        });
      }
    }
  }

  void _applyTyped() {
    if (_form.currentState?.validate() != true) return;
    unawaited(_set(parsePlaybackSpeed(_input.text)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final enabled = !_busy && !_bookChanged;
    final wholeDuration = widget.svc.bookDuration;
    final duration = wholeDuration ?? widget.svc.state.duration;
    final position = wholeDuration == null
        ? widget.svc.state.position
        : widget.svc.bookPosition;
    final mediaLeft = Duration(
      milliseconds: (duration.inMilliseconds - position.inMilliseconds).clamp(
        0,
        duration.inMilliseconds,
      ),
    );
    final listeningLeft = Duration(
      milliseconds: (mediaLeft.inMilliseconds / _speed).ceil(),
    );
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .9,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.speed, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _bookId == null
                          ? 'Playback speed'
                          : 'Speed for this book',
                      style: text.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close speed controls',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '${_speed.toStringAsFixed(2)}×',
                key: const ValueKey('speed-current-value'),
                style: text.headlineMedium?.copyWith(color: cs.primary),
                textAlign: TextAlign.center,
              ),
              if (_bookChanged) ...[
                const SizedBox(height: 8),
                const Text(
                  'The playing book changed. Close this sheet and open speed controls for that book.',
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  for (final preset in presets)
                    ChoiceChip(
                      key: ValueKey('speed-preset-$preset'),
                      label: Text(
                        '${preset.toStringAsFixed(preset.truncate() == preset ? 1 : 2)}×',
                        semanticsLabel: '$preset times speed',
                      ),
                      selected: (_speed - preset).abs() < .005,
                      onSelected: enabled ? (_) => _set(preset) : null,
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  IconButton(
                    key: const ValueKey('speed-decrease'),
                    tooltip: 'Decrease speed by 0.05',
                    onPressed: enabled && _speed > .5
                        ? () => _set(stepPlaybackSpeed(_speed, -1))
                        : null,
                    icon: const Icon(Icons.remove),
                  ),
                  Expanded(
                    child: Semantics(
                      label: 'Playback speed',
                      child: Slider(
                        key: const ValueKey('speed-slider'),
                        min: .5,
                        max: 3,
                        divisions: 50,
                        value: _speed.clamp(.5, 3),
                        label: '${_speed.toStringAsFixed(2)}×',
                        semanticFormatterCallback: (value) =>
                            '${value.toStringAsFixed(2)} times speed',
                        onChangeStart: enabled
                            ? (_) => setState(() => _dragging = true)
                            : null,
                        onChanged: enabled
                            ? (value) => setState(() => _speed = value)
                            : null,
                        onChangeEnd: enabled ? _set : null,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('speed-increase'),
                    tooltip: 'Increase speed by 0.05',
                    onPressed: enabled && _speed < 3
                        ? () => _set(stepPlaybackSpeed(_speed, 1))
                        : null,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const Text(
                '0.50×–3.00× · adjust in 0.05 steps',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Form(
                key: _form,
                child: TextFormField(
                  key: const ValueKey('speed-exact-input'),
                  controller: _input,
                  focusNode: _inputFocus,
                  enabled: enabled,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Exact speed',
                    hintText: 'For example, 1.15',
                    suffixText: '×',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    try {
                      parsePlaybackSpeed(value ?? '');
                      return null;
                    } on FormatException catch (error) {
                      return error.message;
                    }
                  },
                  onFieldSubmitted: (_) => _applyTyped(),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                key: const ValueKey('speed-apply-exact'),
                onPressed: enabled ? _applyTyped : null,
                child: const Text('Apply exact speed'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Semantics(
                  liveRegion: true,
                  child: Text(_error!, style: TextStyle(color: cs.error)),
                ),
              ],
              if (_bookId != null && !_bookChanged) ...[
                const SizedBox(height: 16),
                Container(
                  key: const ValueKey('speed-time-estimate'),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    duration <= Duration.zero
                        ? 'Time remaining will appear when the audio duration is available.'
                        : '${formatDuration(listeningLeft)} of listening left ${wholeDuration == null ? 'in this track' : 'in this book'} at ${_speed.toStringAsFixed(2)}×.\n'
                              '${formatDuration(mediaLeft)} at normal speed.',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This speed is remembered for this book.',
                  style: text.bodySmall,
                ),
              ],
              const SizedBox(height: 16),
              _SpeedProcessingPanel(svc: widget.svc),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SpeedProcessingPanel extends StatelessWidget {
  final PlaybackService svc;
  const _SpeedProcessingPanel({required this.svc});

  @override
  Widget build(BuildContext context) {
    final canChooseDesktop = SpeedProcessing.supportsDesktopChoice();
    final canChooseApple = SpeedProcessing.supportsAppleChoice();
    final selected = DesktopSpeedProcessing.parse(
      svc.settings?.desktopSpeedProcessing ?? 'automatic',
    );
    final current = SpeedProcessing.activeDesktopMode;
    final appleSelected = AppleSpeedProcessing.parse(
      svc.settings?.appleSpeedProcessing ?? 'timeDomain',
    );
    final appleCurrent = SpeedProcessing.activeAppleMode;
    return ExpansionTile(
      key: const ValueKey('speed-processing-panel'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      title: const Text('Speed processing'),
      subtitle: Text(SpeedProcessing.processorLabel()),
      children: [
        Text(SpeedProcessing.description()),
        if (canChooseDesktop && svc.settings != null) ...[
          const SizedBox(height: 8),
          RadioGroup<DesktopSpeedProcessing>(
            groupValue: selected,
            onChanged: (value) {
              if (value != null) {
                svc.settings!.desktopSpeedProcessing = value.id;
              }
            },
            child: Column(
              children: [
                for (final mode in DesktopSpeedProcessing.values)
                  RadioListTile<DesktopSpeedProcessing>(
                    key: ValueKey('speed-processing-${mode.id}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(mode.label),
                    subtitle: Text(
                      mode == DesktopSpeedProcessing.automatic
                          ? 'Use the audio engine’s default pitch preservation.'
                          : 'Use the previous processing path.',
                    ),
                    value: mode,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            selected == current
                ? 'In use: ${current.label}. Changes apply after restarting CrisperPlayer and affect all books.'
                : 'Saved for next launch: ${selected.label}. Restart CrisperPlayer to apply. Currently using ${current.label}.',
            key: const ValueKey('speed-processing-restart'),
          ),
        ],
        if (canChooseApple && svc.settings != null) ...[
          const SizedBox(height: 8),
          RadioGroup<AppleSpeedProcessing>(
            groupValue: appleSelected,
            onChanged: (value) {
              if (value != null) {
                svc.settings!.appleSpeedProcessing = value.id;
              }
            },
            child: Column(
              children: [
                for (final mode in AppleSpeedProcessing.values)
                  RadioListTile<AppleSpeedProcessing>(
                    key: ValueKey('speed-processing-apple-${mode.id}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(mode.label),
                    subtitle: Text(
                      mode == AppleSpeedProcessing.timeDomain
                          ? 'Voice processing · current app default.'
                          : 'Music and mixed audio · more processing power.',
                    ),
                    value: mode,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            appleSelected == appleCurrent
                ? 'In use: ${appleCurrent.label}. Changes apply after restarting CrisperPlayer and affect all books.'
                : 'Saved for next launch: ${appleSelected.label}. Restart CrisperPlayer to apply. Currently using ${appleCurrent.label}.',
            key: const ValueKey('speed-processing-apple-restart'),
          ),
        ],
      ],
    );
  }
}
