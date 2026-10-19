import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/format.dart';
import '../services/audio/playback_service.dart';

Future<void> showSleepTimerSheet(BuildContext context, PlaybackService svc) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _SleepSheet(svc: svc),
  );
}

class _SleepSheet extends StatefulWidget {
  final PlaybackService svc;
  const _SleepSheet({required this.svc});
  @override
  State<_SleepSheet> createState() => _SleepSheetState();
}

class _SleepSheetState extends State<_SleepSheet> {
  final _customForm = GlobalKey<FormState>();
  late final TextEditingController _minutes;
  bool _customChapterEnd = false;
  late Duration _remaining = widget.svc.sleepRemaining;
  late bool _endOfChapter = widget.svc.sleepEndOfChapter;
  late bool _waiting = widget.svc.isWaitingForChapterEnd;

  Timer? _refresh;

  @override
  void dispose() {
    _refresh?.cancel();
    _minutes.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final saved = widget.svc.settings?.sleepTimerDefault.inMinutes ?? 0;
    _minutes = TextEditingController(
      text: '${saved > 0 ? saved.clamp(1, 1440) : 30}',
    );
    _refresh = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _remaining = widget.svc.sleepRemaining;
        _endOfChapter = widget.svc.sleepEndOfChapter;
        _waiting = widget.svc.isWaitingForChapterEnd;
      });
    });
  }

  void _set(Duration d, {bool eoc = false}) {
    widget.svc.setSleepTimer(d, endOfChapter: eoc);
    setState(() {
      _remaining = widget.svc.sleepRemaining;
      _endOfChapter = widget.svc.sleepEndOfChapter;
      _waiting = widget.svc.isWaitingForChapterEnd;
    });
  }

  void _extend(int minutes) {
    widget.svc.extendSleepTimer(Duration(minutes: minutes));
    setState(() {
      _remaining = widget.svc.sleepRemaining;
      _endOfChapter = widget.svc.sleepEndOfChapter;
      _waiting = widget.svc.isWaitingForChapterEnd;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isActive = _remaining != Duration.zero || _waiting || _endOfChapter;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.bedtime_outlined, color: cs.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Sleep timer',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    if (isActive)
                      TextButton.icon(
                        onPressed: () {
                          widget.svc.cancelSleepTimer();
                          setState(() {
                            _remaining = Duration.zero;
                            _endOfChapter = false;
                            _waiting = false;
                          });
                        },
                        icon: const Icon(Icons.close, size: 16),
                        label: const Text('Cancel'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_waiting)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.nights_stay, color: cs.onPrimaryContainer),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Will pause at end of chapter',
                            style: TextStyle(
                              color: cs.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Icon(Icons.hourglass_bottom, size: 16),
                      ],
                    ),
                  )
                else if (_endOfChapter && _remaining != Duration.zero)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          color: cs.onPrimaryContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Sleep in ${formatDuration(_remaining)} → end of chapter',
                            style: TextStyle(
                              color: cs.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (_remaining != Duration.zero)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          color: cs.onPrimaryContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Sleep in ${formatDuration(_remaining)}',
                            style: TextStyle(
                              color: cs.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: cs.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                if (isActive) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: () => _extend(5),
                        child: const Text('+5 minutes'),
                      ),
                      OutlinedButton(
                        onPressed: () => _extend(15),
                        child: const Text('+15 minutes'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                Text(
                  'Presets',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _PresetChip(
                      icon: Icons.timer_10,
                      label: '15 min',
                      selected:
                          _remaining == const Duration(minutes: 15) &&
                          !_endOfChapter,
                      onTap: () => _set(const Duration(minutes: 15)),
                    ),
                    _PresetChip(
                      icon: Icons.timer,
                      label: '30 min',
                      selected:
                          _remaining == const Duration(minutes: 30) &&
                          !_endOfChapter,
                      onTap: () => _set(const Duration(minutes: 30)),
                    ),
                    _PresetChip(
                      icon: Icons.timer_outlined,
                      label: '60 min',
                      selected:
                          _remaining == const Duration(minutes: 60) &&
                          !_endOfChapter,
                      onTap: () => _set(const Duration(minutes: 60)),
                    ),
                    _PresetChip(
                      icon: Icons.bedtime,
                      label: '90 min',
                      selected:
                          _remaining == const Duration(minutes: 90) &&
                          !_endOfChapter,
                      onTap: () => _set(const Duration(minutes: 90)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'End of chapter',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _PresetChip(
                      icon: Icons.menu_book,
                      label: 'End of chapter',
                      selected: _waiting,
                      onTap: () => _set(Duration.zero, eoc: true),
                    ),
                    _PresetChip(
                      icon: Icons.schedule,
                      label: '15 min → EoC',
                      selected:
                          _remaining == const Duration(minutes: 15) &&
                          _endOfChapter,
                      onTap: () => _set(const Duration(minutes: 15), eoc: true),
                    ),
                    _PresetChip(
                      icon: Icons.schedule_outlined,
                      label: '30 min → EoC',
                      selected:
                          _remaining == const Duration(minutes: 30) &&
                          _endOfChapter,
                      onTap: () => _set(const Duration(minutes: 30), eoc: true),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Form(
                  key: _customForm,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        key: const ValueKey('sleep-custom-minutes'),
                        controller: _minutes,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Custom duration in minutes',
                          helperText: '1–1440 minutes of elapsed time',
                        ),
                        validator: (text) {
                          final minutes = int.tryParse(text?.trim() ?? '');
                          return minutes == null ||
                                  minutes < 1 ||
                                  minutes > 1440
                              ? 'Enter a whole number from 1 to 1440.'
                              : null;
                        },
                        onFieldSubmitted: (_) => _startCustom(),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Finish the chapter after the timer'),
                        value: _customChapterEnd,
                        onChanged: (value) =>
                            setState(() => _customChapterEnd = value ?? false),
                      ),
                      OutlinedButton(
                        onPressed: _startCustom,
                        child: const Text('Start custom timer'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _startCustom() {
    if (!_customForm.currentState!.validate()) return;
    final duration = Duration(minutes: int.parse(_minutes.text.trim()));
    widget.svc.settings?.sleepTimerDefault = duration;
    _set(duration, eoc: _customChapterEnd);
    FocusScope.of(context).unfocus();
  }
}

class _PresetChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PresetChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}
