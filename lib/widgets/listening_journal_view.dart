import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/listening_journal.dart';
import '../services/audio/playback_service.dart';
import '../services/db/app_database.dart';
import '../services/settings_service.dart';
import '../utils/format.dart';

/// The optional dated journal has its own recording control. Turning recording
/// off never deletes entries; deletion is a separate explicit action.
class ListeningJournalRecordingControl extends StatefulWidget {
  final PlaybackService playback;
  final SettingsService settings;

  const ListeningJournalRecordingControl({
    super.key,
    required this.playback,
    required this.settings,
  });

  @override
  State<ListeningJournalRecordingControl> createState() =>
      _ListeningJournalRecordingControlState();
}

class _ListeningJournalRecordingControlState
    extends State<ListeningJournalRecordingControl> {
  bool _busy = false;
  String? _error;

  Future<void> _setEnabled(bool enabled) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.playback.setListeningJournalEnabled(enabled);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not change recording: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.settings,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          key: const ValueKey('journal-recording-switch'),
          title: const Text('Keep a listening journal'),
          subtitle: Text(
            widget.settings.listeningJournalEnabled
                ? 'Recording dated playback, pauses, and jumps on this device.'
                : 'Off. Turn on to record future listening. Existing entries remain available.',
          ),
          value: widget.settings.listeningJournalEnabled,
          onChanged: _busy ? null : _setEnabled,
        ),
        if (_busy)
          const LinearProgressIndicator(
            semanticsLabel: 'Updating journal recording',
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ),
      ],
    ),
  );
}

enum _JournalDates { all, today, week, yearAgo, custom }

/// Cursor-paginated journal inspection. Refresh is explicit so incoming
/// playback does not move the historical entries while someone reads them.
class ListeningJournalView extends StatefulWidget {
  final PlaybackService playback;
  final SettingsService settings;
  final DateTime Function()? now;
  final ValueChanged<String>? onOpenPlayer;

  const ListeningJournalView({
    super.key,
    required this.playback,
    required this.settings,
    this.now,
    this.onOpenPlayer,
  });

  @override
  State<ListeningJournalView> createState() => _ListeningJournalViewState();
}

class _ListeningJournalViewState extends State<ListeningJournalView> {
  late final StreamSubscription<List<Book>> _booksSubscription;
  final _scroll = ScrollController();
  final _entries = <ListeningJournalEntry>[];
  final _trackLabels = <String, Map<String, String>>{};
  List<Book> _books = [];
  _JournalDates _dates = _JournalDates.all;
  DateTimeRange? _range;
  String? _bookId;
  String? _nextCursor;
  String? _error;
  String? _openingId;
  String? _openedId;
  String? _openMessage;
  String? _openError;
  bool _loading = false;
  bool _clearing = false;
  int _generation = 0;

  DateTime get _now => (widget.now ?? DateTime.now)();
  DateTime get _today => DateUtils.dateOnly(_now);
  int? get _fromUtcMs => _range?.start.millisecondsSinceEpoch;
  int? get _beforeUtcMs => _range == null
      ? null
      : DateTime(
          _range!.end.year,
          _range!.end.month,
          _range!.end.day + 1,
        ).millisecondsSinceEpoch;

  @override
  void initState() {
    super.initState();
    _booksSubscription = widget.playback.db.watchAllBooks().listen(
      (books) {
        if (mounted) setState(() => _books = books);
      },
      onError: (Object _) {
        // The journal query reports its own actionable database error. A failed
        // book-name lookup must not hide already loaded journal snapshots.
      },
    );
    unawaited(_load(reset: true));
  }

  @override
  void dispose() {
    _generation++;
    _booksSubscription.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({required bool reset}) async {
    if (!reset && (_loading || _nextCursor == null)) return;
    final generation = reset ? ++_generation : _generation;
    final cursor = reset ? null : _nextCursor;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _entries.clear();
        _nextCursor = null;
      }
    });
    if (reset && _scroll.hasClients) _scroll.jumpTo(0);
    try {
      final page = await widget.playback.listeningJournal(
        bookId: _bookId,
        fromUtcMs: _fromUtcMs,
        beforeUtcMs: _beforeUtcMs,
        limit: 50,
        cursor: cursor,
      );
      final labels = <String, Map<String, String>>{};
      for (final id in page.entries.map((entry) => entry.bookId).toSet()) {
        if (_trackLabels.containsKey(id)) continue;
        final tracks = await widget.playback.db.tracksFor(id);
        labels[id] = {
          for (final track in tracks)
            track.filePath:
                'Track ${track.trackIndex + 1} · ${safeBasename(track.filePath)}',
        };
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        final existing = _entries.map((entry) => entry.id).toSet();
        _entries.addAll(page.entries.where((entry) => existing.add(entry.id)));
        _trackLabels.addAll(labels);
        _nextCursor = page.nextCursor;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = 'Could not load the journal: $error');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _setDates(_JournalDates dates) {
    final today = _today;
    final DateTimeRange? range;
    switch (dates) {
      case _JournalDates.all:
        range = null;
      case _JournalDates.today:
        range = DateTimeRange(start: today, end: today);
      case _JournalDates.week:
        range = DateTimeRange(
          start: DateTime(today.year, today.month, today.day - 6),
          end: today,
        );
      case _JournalDates.yearAgo:
        final day = math.min(
          today.day,
          DateUtils.getDaysInMonth(today.year - 1, today.month),
        );
        final earlier = DateTime(today.year - 1, today.month, day);
        range = DateTimeRange(start: earlier, end: earlier);
      case _JournalDates.custom:
        unawaited(_chooseDates());
        return;
    }
    setState(() {
      _dates = dates;
      _range = range;
    });
    unawaited(_load(reset: true));
  }

  Future<void> _chooseDates() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1970),
      lastDate: _today,
      initialDateRange: _range ?? DateTimeRange(start: _today, end: _today),
      helpText: 'Choose journal dates',
    );
    if (range == null || !mounted) return;
    setState(() {
      _dates = _JournalDates.custom;
      _range = range;
    });
    await _load(reset: true);
  }

  Future<void> _clear() async {
    if (_clearing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: const Text('Clear listening journal?'),
        content: const Text(
          'Permanently delete all dated journal entries on this device? '
          'This clears every book and date, including entries outside the current filter. '
          'Books, bookmarks, the listening map, and session history remain available.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('journal-confirm-clear'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear journal'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _clearing = true);
    try {
      await widget.playback.clearListeningJournal();
      if (!mounted) return;
      setState(() {
        _openedId = null;
        _openMessage = null;
        _openError = null;
      });
      await _load(reset: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Listening journal cleared')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not clear the journal: $error');
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  Future<void> _open(
    ListeningJournalEntry entry,
    String filePath,
    int positionMs,
  ) async {
    if (_openingId != null || _clearing) return;
    setState(() {
      _openingId = entry.id;
      _openedId = null;
      _openMessage = null;
      _openError = null;
    });
    try {
      final bookmarkId = await widget.playback.resumeJournalPosition(
        bookId: entry.bookId,
        filePath: filePath,
        positionMs: positionMs,
      );
      if (mounted) {
        setState(() {
          _openedId = entry.id;
          _openMessage =
              'Opened at ${_timecode(positionMs)}. Playback is paused.'
              '${bookmarkId != null ? ' Your previous place is saved in “Before journal jump”.' : ''}';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _openedId = entry.id;
          _openError = 'Could not open this recorded position: $error';
        });
      }
    } finally {
      if (mounted) setState(() => _openingId = null);
    }
  }

  @override
  Widget build(BuildContext context) => ListView.builder(
    key: const ValueKey('listening-journal-scroll'),
    controller: _scroll,
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
    itemCount: _entries.length + 2,
    itemBuilder: (context, index) {
      if (index == 0) return _header(context);
      if (index == _entries.length + 1) return _footer(context);
      final entry = _entries[index - 1];
      final date = DateTime.fromMillisecondsSinceEpoch(entry.startedAtMs);
      final previous = index > 1
          ? DateTime.fromMillisecondsSinceEpoch(_entries[index - 2].startedAtMs)
          : null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (previous == null || !DateUtils.isSameDay(previous, date))
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Text(
                DateFormat.yMMMMd().format(date),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          _entry(context, entry),
        ],
      );
    },
  );

  Widget _header(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final books = [..._books]
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    final selectedMissing =
        _bookId != null && !books.any((book) => book.id == _bookId);
    final rangeLabel = _range == null
        ? 'All recorded dates'
        : DateUtils.isSameDay(_range!.start, _range!.end)
        ? DateFormat.yMMMd().format(_range!.start)
        : '${DateFormat.yMMMd().format(_range!.start)} – ${DateFormat.yMMMd().format(_range!.end)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Your listening, in time', style: text.headlineSmall),
        const SizedBox(height: 8),
        const Text(
          'Find a past listening day, see where you stopped or jumped, and open that exact position paused.',
        ),
        const SizedBox(height: 12),
        Card.outlined(
          margin: EdgeInsets.zero,
          child: ListeningJournalRecordingControl(
            playback: widget.playback,
            settings: widget.settings,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Optional and stored on this device. Entries stay until you clear them or delete the book, and are included in library backups. Earlier listening is not recreated.',
          style: text.bodySmall,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final choice in <_JournalDates, String>{
              _JournalDates.all: 'All dates',
              _JournalDates.today: 'Today',
              _JournalDates.week: 'Last 7 days',
              _JournalDates.yearAgo: 'A year ago',
              _JournalDates.custom: 'Choose dates',
            }.entries)
              ChoiceChip(
                key: ValueKey('journal-dates-${choice.key.name}'),
                label: Text(choice.value),
                selected: _dates == choice.key,
                onSelected: (_) => _setDates(choice.key),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          rangeLabel,
          key: const ValueKey('journal-date-range'),
          style: text.titleSmall,
        ),
        const SizedBox(height: 4),
        Text(
          'Dates and times use this device’s local time.',
          style: text.bodySmall,
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('journal-book-filter-${_bookId ?? 'all'}'),
          initialValue: _bookId ?? '',
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'Book',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('All books')),
            for (final book in books)
              DropdownMenuItem(
                value: book.id,
                child: Text(
                  book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (selectedMissing)
              DropdownMenuItem(
                value: _bookId,
                child: const Text('Unavailable book'),
              ),
          ],
          onChanged: (value) {
            setState(
              () => _bookId = value == null || value.isEmpty ? null : value,
            );
            unawaited(_load(reset: true));
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('journal-refresh'),
              onPressed: _loading || _clearing
                  ? null
                  : () => _load(reset: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
            TextButton.icon(
              key: const ValueKey('journal-clear'),
              onPressed: _clearing || _openingId != null ? null : _clear,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Clear journal'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Newest first. Refresh to include new recording. Gaps without entries do not prove that audio was never played.',
          style: text.bodySmall,
        ),
        const SizedBox(height: 12),
        if (_loading || _clearing)
          const LinearProgressIndicator(
            semanticsLabel: 'Loading listening journal',
          ),
      ],
    );
  }

  Widget _entry(BuildContext context, ListeningJournalEntry entry) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final played = entry.kind == 'played';
    final jump = entry.kind == 'seek';
    final start = DateTime.fromMillisecondsSinceEpoch(entry.startedAtMs);
    final end = DateTime.fromMillisecondsSinceEpoch(entry.endedAtMs);
    final dateFormat = DateFormat.Hms();
    final when = played && entry.endedAtMs != entry.startedAtMs
        ? '${dateFormat.format(start)} – ${DateUtils.isSameDay(start, end) ? dateFormat.format(end) : '${DateFormat.yMMMd().format(end)} ${dateFormat.format(end)}'}'
        : dateFormat.format(start);
    final title = entry.bookTitle.trim().isEmpty
        ? entry.bookId
        : entry.bookTitle;
    Widget position(
      String prefix,
      String filePath,
      int milliseconds,
    ) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        '$prefix: ${_trackLabels[entry.bookId]?[filePath] ?? safeBasename(filePath)} · ${_timecode(milliseconds)}',
        style: text.bodyMedium,
      ),
    );
    Widget action(
      String label,
      String filePath,
      int milliseconds,
      String suffix,
    ) => OutlinedButton(
      key: ValueKey('journal-open-${entry.id}-$suffix'),
      onPressed: _openingId != null || _clearing
          ? null
          : () => _open(entry, filePath, milliseconds),
      child: Text(label),
    );
    return Card.outlined(
      key: ValueKey('journal-entry-${entry.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _journalIcon(entry.kind),
                  color: played ? cs.primary : cs.tertiary,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(_journalLabel(entry), style: text.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(title, style: text.titleMedium),
            const SizedBox(height: 4),
            Text(when, style: text.bodySmall),
            if (entry.chapterTitle?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 6),
              Text(
                '${played ? 'Chapter at start' : 'Chapter'}: ${entry.chapterTitle}',
                style: text.bodySmall,
              ),
            ],
            if (jump) ...[
              position('From', entry.filePath, entry.startMs),
              if (entry.targetFilePath != null &&
                  entry.targetPositionMs != null)
                position('To', entry.targetFilePath!, entry.targetPositionMs!)
              else
                const Text('The destination was not recorded.'),
            ] else if (played) ...[
              position('From', entry.filePath, entry.startMs),
              Text(
                'To: ${_timecode(entry.endMs)} · ${formatSpokenDuration(Duration(milliseconds: entry.endMs - entry.startMs))} of audio',
                style: text.bodyMedium,
              ),
            ] else
              position('Position', entry.filePath, entry.endMs),
            const SizedBox(height: 6),
            Text(
              '${entry.speed.toStringAsFixed(2)}× · recorded zone ${_utcOffset(entry.utcOffsetMinutes)}',
              style: text.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (jump) ...[
                  action(
                    'Open from paused',
                    entry.filePath,
                    entry.startMs,
                    'from',
                  ),
                  if (entry.targetFilePath != null &&
                      entry.targetPositionMs != null)
                    action(
                      'Open to paused',
                      entry.targetFilePath!,
                      entry.targetPositionMs!,
                      'to',
                    ),
                ] else if (played) ...[
                  action(
                    'Open start paused',
                    entry.filePath,
                    entry.startMs,
                    'start',
                  ),
                  action('Open end paused', entry.filePath, entry.endMs, 'end'),
                ] else
                  action(
                    'Open position paused',
                    entry.filePath,
                    entry.endMs,
                    'position',
                  ),
              ],
            ),
            if (_openingId == entry.id)
              const LinearProgressIndicator(
                semanticsLabel: 'Opening recorded position',
              ),
            if (_openedId == entry.id &&
                (_openMessage != null || _openError != null)) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Text(
                  _openError ?? _openMessage!,
                  style: text.bodySmall?.copyWith(
                    color: _openError != null ? cs.error : cs.onSurface,
                  ),
                ),
              ),
              if (_openError == null && widget.onOpenPlayer != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => widget.onOpenPlayer!(entry.bookId),
                    icon: const Icon(Icons.headphones),
                    label: const Text('Open player'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _footer(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_error != null) ...[
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        OutlinedButton(
          onPressed: () => _load(reset: _entries.isEmpty),
          child: const Text('Try again'),
        ),
      ] else if (!_loading && _entries.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'No journal entries for these dates and this book. Choose another range, or turn on recording for future listening.',
            key: const ValueKey('journal-empty'),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      if (_nextCursor != null) ...[
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const ValueKey('journal-load-more'),
          onPressed: _loading ? null : () => _load(reset: false),
          icon: const Icon(Icons.expand_more),
          label: Text(_loading ? 'Loading…' : 'Load older entries'),
        ),
      ],
    ],
  );
}

String _timecode(int milliseconds) {
  final whole = formatDuration(Duration(milliseconds: milliseconds));
  final fraction = milliseconds.remainder(1000);
  return fraction == 0
      ? whole
      : '$whole.${fraction.toString().padLeft(3, '0')}';
}

String _utcOffset(int minutes) =>
    'UTC${minutes < 0 ? '−' : '+'}'
    '${(minutes.abs() ~/ 60).toString().padLeft(2, '0')}:'
    '${(minutes.abs() % 60).toString().padLeft(2, '0')}';

IconData _journalIcon(String kind) => switch (kind) {
  'played' => Icons.graphic_eq,
  'play' => Icons.play_circle_outline,
  'pause' => Icons.pause_circle_outline,
  'stop' => Icons.stop_circle_outlined,
  'seek' => Icons.swap_horiz,
  'complete' => Icons.task_alt,
  'interruption' => Icons.hearing_disabled_outlined,
  'open' => Icons.folder_open,
  'close' => Icons.close,
  _ => Icons.history,
};

String _journalLabel(ListeningJournalEntry entry) {
  if (entry.kind == 'played') {
    return entry.reason == 'return_trail' ? 'Return Trail replay' : 'Played';
  }
  if (entry.kind == 'seek') {
    return switch (entry.reason) {
      'chapter' => 'Opened a chapter',
      'next_chapter' => 'Jumped to the next chapter',
      'previous_chapter' => 'Jumped to the previous chapter',
      'next_track' => 'Jumped to the next track',
      'previous_track' => 'Jumped to the previous track',
      'skip_forward' => 'Skipped forward',
      'skip_back' => 'Skipped back',
      'smart_rewind' => 'Smart rewind',
      'bookmark' => 'Opened a bookmark',
      'coverage_jump' => 'Jumped from the listening map',
      'journal_resume' => 'Opened a journal position',
      'return_trail' => 'Opened a Return Trail passage',
      'return_trail_return' => 'Returned to the saved place',
      'return_trail_continue' => 'Chose the Return Trail position',
      'restart' => 'Restarted the book',
      'mark_unread' => 'Reset to unread',
      _ => 'Jumped',
    };
  }
  return switch (entry.kind) {
    'play' => 'Started playback',
    'pause' => 'Paused',
    'stop' => 'Stopped',
    'complete' => 'Reached the end',
    'interruption' => 'Playback interrupted',
    'open' => 'Opened the book',
    'close' => 'Closed the book',
    _ => 'Listening event',
  };
}
