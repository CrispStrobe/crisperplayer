import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/book_preferences.dart';
import '../providers/providers.dart';
import '../services/db/app_database.dart';
import '../utils/platform_utils.dart';

Future<void> showBookPreferences(BuildContext context, Book book) => showDialog(
  context: context,
  builder: (_) => _BookPreferences(book: book),
);

class _BookPreferences extends ConsumerStatefulWidget {
  final Book book;
  const _BookPreferences({required this.book});
  @override
  ConsumerState<_BookPreferences> createState() => _BookPreferencesState();
}

class _BookPreferencesState extends ConsumerState<_BookPreferences> {
  late final Map<String, dynamic> _values = BookPreferences.decode(
    widget.book.playbackPreferencesJson,
  );
  String? _error;
  bool _busy = false;
  Widget _choice(
    String key,
    String label,
    List<num> options, {
    String suffix = 's',
  }) {
    final values = {
      ...options,
      if (_values[key] is num) _values[key] as num,
    }.toList()..sort((a, b) => a.compareTo(b));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        initialValue: _values[key]?.toString() ?? 'inherit',
        decoration: InputDecoration(labelText: label),
        items: [
          const DropdownMenuItem(
            value: 'inherit',
            child: Text('Use app default'),
          ),
          for (final value in values)
            DropdownMenuItem(
              value: value.toString(),
              child: Text('$value$suffix'),
            ),
        ],
        onChanged: _busy
            ? null
            : (value) {
                _values[key] = value == 'inherit'
                    ? null
                    : {'speed', 'boostDb'}.contains(key)
                    ? double.parse(value!)
                    : int.parse(value!);
              },
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(playbackProvider)
          .updateBookPreferences(widget.book.id, _values, reset: true);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Playback for this book'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Overrides apply only to this book. Choose “Use app default” to inherit settings.',
            ),
            const SizedBox(height: 16),
            _choice('speed', 'Playback speed', [
              .5,
              .8,
              1.0,
              1.25,
              1.5,
              1.75,
              2.0,
              2.5,
              3.0,
            ], suffix: '×'),
            _choice('seekSeconds', 'Skip interval', [10, 15, 30, 60]),
            _choice('smartRewindSeconds', 'Smart rewind amount (0 disables)', [
              0,
              3,
              5,
              10,
              15,
              30,
              60,
            ]),
            _choice(
              'smartRewindAfterSeconds',
              'Rewind after a pause longer than',
              [0, 30, 60, 120, 300, 600],
            ),
            if (isAndroid) ...[
              _choice('boostDb', 'Voice boost', [
                0,
                3,
                6,
                9,
                12,
              ], suffix: ' dB'),
              DropdownButtonFormField<String>(
                initialValue: _values['equalizer'] as String? ?? 'inherit',
                decoration: const InputDecoration(labelText: 'Equalizer'),
                items: const [
                  DropdownMenuItem(
                    value: 'inherit',
                    child: Text('Use app default'),
                  ),
                  DropdownMenuItem(value: 'off', child: Text('Off')),
                  DropdownMenuItem(
                    value: 'speech',
                    child: Text('Speech clarity'),
                  ),
                  DropdownMenuItem(value: 'warm', child: Text('Warm')),
                  DropdownMenuItem(
                    value: 'bass-reduction',
                    child: Text('Reduce bass'),
                  ),
                ],
                onChanged: _busy
                    ? null
                    : (v) => _values['equalizer'] = v == 'inherit' ? null : v,
              ),
              const SizedBox(height: 12),
            ],
            DropdownButtonFormField<String>(
              initialValue: _values['skipSilence']?.toString() ?? 'inherit',
              decoration: const InputDecoration(labelText: 'Skip silence'),
              items: const [
                DropdownMenuItem(
                  value: 'inherit',
                  child: Text('Use app default'),
                ),
                DropdownMenuItem(value: 'true', child: Text('On')),
                DropdownMenuItem(value: 'false', child: Text('Off')),
              ],
              onChanged: isAndroid && !_busy
                  ? (value) => _values['skipSilence'] = value == 'inherit'
                        ? null
                        : value == 'true'
                  : null,
            ),
            if (!isAndroid) const Text('Skip silence is available on Android.'),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: Text(_busy ? 'Saving…' : 'Save'),
      ),
    ],
  );
}
