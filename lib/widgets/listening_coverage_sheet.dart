import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/listening_coverage.dart';
import '../models/listening_journal.dart';
import '../models/playback_state.dart';
import '../services/audio/playback_service.dart';
import '../services/listening_coverage_service.dart';
import '../utils/format.dart';
import 'listening_journal_view.dart';

Future<void> showListeningCoverageSheet(
  BuildContext context,
  PlaybackService playback, {
  required String bookId,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => ListeningCoverageSheet(playback: playback, bookId: bookId),
);

class ListeningCoverageCard extends StatefulWidget {
  final PlaybackService playback;
  final String bookId;

  const ListeningCoverageCard({
    super.key,
    required this.playback,
    required this.bookId,
  });

  @override
  State<ListeningCoverageCard> createState() => _ListeningCoverageCardState();
}

class _ListeningCoverageCardState extends State<ListeningCoverageCard> {
  late Stream<BookListeningCoverage> _coverage;

  void _subscribe() {
    _coverage = ListeningCoverageService(
      widget.playback.db,
    ).watch(widget.bookId);
  }

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant ListeningCoverageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookId != widget.bookId ||
        oldWidget.playback != widget.playback) {
      _subscribe();
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<BookListeningCoverage>(
    stream: _coverage,
    builder: (context, snapshot) {
      final coverage = snapshot.data;
      final cs = Theme.of(context).colorScheme;
      final played = <CoverageInterval>[];
      if (coverage?.durationMs != null) {
        var offset = 0;
        for (final track in coverage!.tracks) {
          for (final interval in track.played) {
            played.add(
              CoverageInterval(
                startMs: offset + interval.startMs,
                endMs: offset + interval.endMs,
              ),
            );
          }
          offset += track.durationMs!;
        }
      }
      return Card.outlined(
        key: const ValueKey('listening-coverage-card'),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showListeningCoverageSheet(
            context,
            widget.playback,
            bookId: widget.bookId,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.view_timeline_outlined,
                      color: cs.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Listening map',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right, size: 20),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  coverage != null
                      ? _bookSummary(coverage)
                      : snapshot.hasError
                      ? 'Open to retry your listening map'
                      : 'Loading recorded playback…',
                  key: const ValueKey('listening-coverage-card-summary'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (coverage?.durationMs != null && coverage!.durationMs! > 0)
                  ExcludeSemantics(
                    child: SizedBox(
                      height: 24,
                      child: CustomPaint(
                        painter: _CoveragePainter(
                          played: played,
                          extentMs: coverage.durationMs!,
                          playedColor: cs.primary,
                          emptyColor: cs.surfaceContainerHighest,
                          hatchColor: cs.outlineVariant,
                          markerColor: cs.onSurface,
                          selectionColor: cs.tertiary,
                          surfaceColor: cs.surface,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

String _bookSummary(BookListeningCoverage coverage) {
  final time = _mapTime(coverage.playedMs);
  return coverage.durationMs == null
      ? '$time recorded · total length unknown'
      : '$time played · ${_recordedPercent(coverage.playedMs, coverage.durationMs!)}% recorded';
}

int _recordedPercent(int playedMs, int durationMs) =>
    durationMs <= 0 ? 0 : (playedMs * 100 ~/ durationMs).clamp(0, 100);

String _mapTime(int milliseconds) {
  final whole = formatDuration(Duration(milliseconds: milliseconds));
  final fraction = milliseconds.remainder(1000);
  return fraction == 0
      ? whole
      : '$whole.${fraction.toString().padLeft(3, '0')}';
}

String _preciseSpokenDuration(int milliseconds) {
  if (milliseconds.remainder(1000) == 0) {
    return formatSpokenDuration(Duration(milliseconds: milliseconds));
  }
  if (milliseconds < 1000) return '$milliseconds milliseconds';
  final fraction = milliseconds
      .remainder(1000)
      .toString()
      .padLeft(3, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return '${milliseconds ~/ 1000}.$fraction seconds';
}

class ListeningCoverageSheet extends StatefulWidget {
  final PlaybackService playback;
  final String bookId;

  const ListeningCoverageSheet({
    super.key,
    required this.playback,
    required this.bookId,
  });

  @override
  State<ListeningCoverageSheet> createState() => _ListeningCoverageSheetState();
}

class _ListeningCoverageSheetState extends State<ListeningCoverageSheet> {
  late final StreamSubscription<BookListeningCoverage> _coverageSubscription;
  late final StreamSubscription<PlaybackState> _playbackSubscription;
  BookListeningCoverage? _coverage;
  _CoverageSelection? _selection;
  String? _error;
  String? _actionError;
  String? _confirmation;
  bool _busy = false;

  bool get _sameBook => widget.playback.currentBookId == widget.bookId;

  @override
  void initState() {
    super.initState();
    _coverageSubscription = ListeningCoverageService(widget.playback.db)
        .watch(widget.bookId)
        .listen(
          (coverage) {
            if (mounted) {
              setState(() {
                _coverage = coverage;
                _error = null;
              });
            }
          },
          onError: (Object error) {
            if (mounted) {
              setState(
                () => _error = 'Could not load your listening map: $error',
              );
            }
          },
        );
    _playbackSubscription = widget.playback.stateStream.listen((_) {
      if (mounted) setState(() {});
    });
    unawaited(_refresh());
  }

  Future<void> _refresh() async {
    try {
      final coverage = await widget.playback.listeningCoverage(
        bookId: widget.bookId,
      );
      if (mounted) {
        setState(() {
          _coverage = coverage;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not refresh your listening map: $error');
      }
    }
  }

  @override
  void dispose() {
    _coverageSubscription.cancel();
    _playbackSubscription.cancel();
    super.dispose();
  }

  void _select(TrackListeningCoverage track, int positionMs, {int? gapEndMs}) {
    if (_busy) return;
    setState(() {
      _selection = _CoverageSelection(
        track: track,
        positionMs: positionMs,
        gapEndMs: gapEndMs,
      );
      _actionError = null;
      _confirmation = null;
    });
  }

  void _nextGap() {
    if (_busy || !_sameBook) return;
    final all = [
      for (final track in _coverage?.tracks ?? <TrackListeningCoverage>[])
        for (final gap in track.gaps) (track: track, gap: gap),
    ];
    if (all.isEmpty) return;
    final selection = _selection;
    final state = widget.playback.state;
    final cursorTrack = selection?.track.trackIndex ?? state.currentIndex;
    final cursorMs =
        selection?.gapEndMs ??
        selection?.positionMs ??
        state.position.inMilliseconds;
    final after = all.where(
      (entry) =>
          entry.track.trackIndex > cursorTrack ||
          (entry.track.trackIndex == cursorTrack && entry.gap.endMs > cursorMs),
    );
    final wrapped = after.isEmpty;
    final entry = wrapped ? all.first : after.first;
    final target = !wrapped && entry.track.trackIndex == cursorTrack
        ? math.max(entry.gap.startMs, cursorMs)
        : entry.gap.startMs;
    setState(() {
      _selection = _CoverageSelection(
        track: entry.track,
        positionMs: target,
        gapEndMs: entry.gap.endMs,
        wrapped: wrapped,
        fromGapAction: true,
      );
      _actionError = null;
      _confirmation = null;
    });
  }

  Future<void> _jump(_CoverageSelection selection) async {
    if (_busy) return;
    if (!_sameBook) {
      setState(
        () => _actionError =
            'The playing book changed. Open its listening map to jump.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _actionError = null;
      _confirmation = null;
    });
    try {
      await widget.playback.seekCoverage(
        bookId: widget.bookId,
        filePath: selection.track.filePath,
        positionMs: selection.positionMs,
      );
      if (mounted && _sameBook) {
        setState(
          () => _confirmation =
              'Opened at ${_mapTime(selection.positionMs)}. Playback is paused.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _actionError = 'Could not open that position: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final coverage = _coverage;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .84,
        child: ListView.builder(
          key: const ValueKey('listening-coverage-scroll'),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          itemCount: 1 + (coverage?.tracks.length ?? 0),
          itemBuilder: (context, index) => index == 0
              ? _header(context, coverage)
              : _track(context, coverage!.tracks[index - 1]),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, BookListeningCoverage? coverage) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final hasGaps =
        coverage?.tracks.any((track) => track.gaps.isNotEmpty) ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.view_timeline_outlined, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(child: Text('Listening map', style: text.titleLarge)),
            IconButton(
              tooltip: 'Close listening map',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'See where you have played, and where the gaps are.',
          style: text.bodyLarge,
        ),
        const SizedBox(height: 12),
        if (coverage != null) ...[
          Text(
            _bookSummary(coverage),
            key: const ValueKey('listening-coverage-summary'),
            style: text.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Replayed sections count once. Older listening, playback on other devices, and skipped silence may have no recorded coverage.',
            style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          const _CoverageLegend(),
          const SizedBox(height: 12),
          Text(
            'Select a point to see its Playback dates, or choose Jump here to open it paused.',
            style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          if (!_sameBook) ...[
            const SizedBox(height: 12),
            const Text(
              'The playing book changed. You can still inspect its playback dates. Open this book in the player to jump within its map.',
            ),
          ],
          if (hasGaps) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey('listening-coverage-next-gap'),
                onPressed: _busy || !_sameBook ? null : _nextGap,
                icon: const Icon(Icons.skip_next_outlined),
                label: const Text('Next gap'),
              ),
            ),
          ],
          if (_selection?.fromGapAction == true) ...[
            const SizedBox(height: 8),
            _selectionControls(context, _selection!, header: true),
          ],
          if (coverage.tracks.isEmpty) ...[
            const SizedBox(height: 16),
            const Text('No tracks are available for this book.'),
          ],
        ] else if (_error == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: LinearProgressIndicator(
              semanticsLabel: 'Loading listening map',
            ),
          ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: TextStyle(color: cs.error)),
          OutlinedButton.icon(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _track(BuildContext context, TrackListeningCoverage track) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final state = widget.playback.state;
    final current = _sameBook && state.currentFile == track.filePath;
    final extent = track.durationMs ?? track.timelineExtentMs;
    final position = current ? state.position.inMilliseconds : null;
    final selection = _selection?.track.filePath == track.filePath
        ? _selection
        : null;
    final playedTime = _mapTime(track.playedMs);
    final summary = track.durationMs == null
        ? '$playedTime played · end unknown'
        : '$playedTime of ${_mapTime(track.durationMs!)} played · ${_recordedPercent(track.playedMs, track.durationMs!)}%';
    return Container(
      key: ValueKey('listening-coverage-track-${track.trackIndex}'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: current ? cs.primary : cs.outlineVariant),
        borderRadius: BorderRadius.circular(14),
        color: cs.surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Track ${track.trackIndex + 1} · ${track.title}',
            style: text.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            summary,
            key: ValueKey(
              'listening-coverage-track-summary-${track.trackIndex}',
            ),
            style: text.bodySmall,
          ),
          ListeningCoverageTimeline(
            key: ValueKey('listening-coverage-timeline-${track.trackIndex}'),
            played: track.played,
            extentMs: extent,
            playedMs: track.playedMs,
            durationKnown: track.durationMs != null,
            playheadMs: position,
            selectedMs: selection?.positionMs,
            label: 'Track ${track.trackIndex + 1} listening map',
            stepMs: widget.playback.seekSeconds * 1000,
            onSelected: _busy || extent <= 0
                ? null
                : (milliseconds) => _select(track, milliseconds),
          ),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 16,
            runSpacing: 4,
            children: [
              Text('00:00', style: text.labelSmall),
              Text(
                track.durationMs == null
                    ? 'Recorded through ${_mapTime(extent)} · end unknown'
                    : _mapTime(extent),
                style: text.labelSmall,
              ),
            ],
          ),
          if (current) ...[
            const SizedBox(height: 8),
            Text(
              'Current position: ${_mapTime(state.position.inMilliseconds)}${position! > extent ? ' · beyond the recorded range' : ''}',
              style: text.bodySmall,
            ),
          ],
          if (track.played.isEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'No playback recorded for this track.',
              style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
          if (track.gaps.isNotEmpty) ...[
            const SizedBox(height: 8),
            Material(
              type: MaterialType.transparency,
              child: ExpansionTile(
                key: ValueKey('listening-coverage-gaps-${track.trackIndex}'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(
                  '${track.gaps.length} ${track.gaps.length == 1 ? 'gap' : 'gaps'} with no playback recorded',
                  style: text.bodySmall,
                ),
                children: [
                  for (final gap in track.gaps)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.radio_button_unchecked,
                        size: 20,
                      ),
                      title: Text(
                        '${_mapTime(gap.startMs)}–${_mapTime(gap.endMs)}',
                        style: text.bodyMedium,
                      ),
                      subtitle: Text(
                        '${_preciseSpokenDuration(gap.lengthMs)} without recorded playback',
                      ),
                      onTap: _busy
                          ? null
                          : () => _select(
                              track,
                              gap.startMs,
                              gapEndMs: gap.endMs,
                            ),
                    ),
                ],
              ),
            ),
          ],
          if (selection != null) ...[
            const SizedBox(height: 12),
            _selectionControls(context, selection, header: false),
          ],
        ],
      ),
    );
  }

  Widget _selectionControls(
    BuildContext context,
    _CoverageSelection selection, {
    required bool header,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (selection.wrapped)
          const Text(
            'Wrapped to an earlier gap.',
            key: ValueKey('listening-coverage-wrapped'),
          ),
        Text(
          'Selected: track ${selection.track.trackIndex + 1} · ${_mapTime(selection.positionMs)}${selection.gapEndMs == null ? '' : '–${_mapTime(selection.gapEndMs!)}'}',
          key: ValueKey(
            'listening-coverage-selected-${header ? 'header' : selection.track.trackIndex}',
          ),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        if (widget.playback.isReturnTrailActive) ...[
          Text(
            'Jump here ends Return Trail and opens this point paused.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilledButton.icon(
              key: ValueKey(
                'listening-coverage-jump-${header ? 'header' : selection.track.trackIndex}',
              ),
              onPressed: _busy || !_sameBook ? null : () => _jump(selection),
              icon: const Icon(Icons.near_me_outlined),
              label: const Text('Jump here'),
            ),
            if (widget.playback.settings != null)
              OutlinedButton.icon(
                key: ValueKey(
                  'listening-coverage-dates-${header ? 'header' : selection.track.trackIndex}',
                ),
                onPressed: _busy
                    ? null
                    : () => showPassageListeningJournal(
                        context,
                        playback: widget.playback,
                        settings: widget.playback.settings!,
                        passage: selection.gapEndMs == null
                            ? JournalPassageFilter.point(
                                bookId: widget.bookId,
                                filePath: selection.track.filePath,
                                positionMs: selection.positionMs,
                              )
                            : JournalPassageFilter.range(
                                bookId: widget.bookId,
                                filePath: selection.track.filePath,
                                startMs: selection.positionMs,
                                endMs: selection.gapEndMs!,
                              ),
                        trackLabel: 'Track ${selection.track.trackIndex + 1}',
                      ),
                icon: const Icon(Icons.history),
                label: const Text('Playback dates'),
              ),
          ],
        ),
        if (_confirmation != null) ...[
          const SizedBox(height: 6),
          Semantics(
            liveRegion: true,
            child: Text(
              _confirmation!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
        if (_actionError != null) ...[
          const SizedBox(height: 6),
          Semantics(
            liveRegion: true,
            child: Text(_actionError!, style: TextStyle(color: cs.error)),
          ),
        ],
      ],
    );
  }
}

class _CoverageSelection {
  final TrackListeningCoverage track;
  final int positionMs;
  final int? gapEndMs;
  final bool wrapped;
  final bool fromGapAction;

  const _CoverageSelection({
    required this.track,
    required this.positionMs,
    this.gapEndMs,
    this.wrapped = false,
    this.fromGapAction = false,
  });
}

/// Pointer and keyboard input select a position. Only the separate Jump here
/// command changes playback, so inspecting a gap cannot lose the current place.
class ListeningCoverageTimeline extends StatefulWidget {
  final List<CoverageInterval> played;
  final int extentMs;
  final int playedMs;
  final bool durationKnown;
  final int? playheadMs;
  final int? selectedMs;
  final String label;
  final int stepMs;
  final ValueChanged<int>? onSelected;

  const ListeningCoverageTimeline({
    super.key,
    required this.played,
    required this.extentMs,
    required this.playedMs,
    required this.durationKnown,
    required this.label,
    this.playheadMs,
    this.selectedMs,
    this.stepMs = 30000,
    this.onSelected,
  });

  @override
  State<ListeningCoverageTimeline> createState() =>
      _ListeningCoverageTimelineState();
}

class _ListeningCoverageTimelineState extends State<ListeningCoverageTimeline> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final extent = math.max(0, widget.extentMs);
    final enabled = widget.onSelected != null && extent > 0;
    final selected = (widget.selectedMs ?? widget.playheadMs ?? 0).clamp(
      0,
      extent,
    );
    final next = (selected + widget.stepMs).clamp(0, extent);
    final previous = (selected - widget.stepMs).clamp(0, extent);
    String time(int value) => _preciseSpokenDuration(value);
    return Semantics(
      container: true,
      slider: enabled,
      enabled: enabled,
      label: widget.label,
      value:
          '${time(widget.playedMs)} of playback recorded. ${widget.durationKnown ? '${time(extent)} total.' : 'Track end unknown; recorded through ${time(extent)}.'} Selected ${time(selected)}.',
      increasedValue: enabled && next > selected
          ? 'Selected ${time(next)}'
          : null,
      decreasedValue: enabled && previous < selected
          ? 'Selected ${time(previous)}'
          : null,
      onIncrease: enabled && next > selected
          ? () => widget.onSelected!(next)
          : null,
      onDecrease: enabled && previous < selected
          ? () => widget.onSelected!(previous)
          : null,
      child: Focus(
        focusNode: _focus,
        canRequestFocus: enabled,
        onKeyEvent: (_, event) {
          if (!enabled || event is! KeyDownEvent) return KeyEventResult.ignored;
          final int target;
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            target = next;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            target = previous;
          } else if (event.logicalKey == LogicalKeyboardKey.home) {
            target = 0;
          } else if (event.logicalKey == LogicalKeyboardKey.end) {
            target = extent;
          } else {
            return KeyEventResult.ignored;
          }
          widget.onSelected!(target);
          return KeyEventResult.handled;
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            void select(Offset offset) {
              if (!enabled) return;
              _focus.requestFocus();
              final width = math.max(1.0, constraints.maxWidth - 16);
              final fraction = ((offset.dx - 8) / width).clamp(0.0, 1.0);
              widget.onSelected!((fraction * extent).round());
            }

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTapDown: enabled
                  ? (details) => select(details.localPosition)
                  : null,
              onHorizontalDragUpdate: enabled
                  ? (details) => select(details.localPosition)
                  : null,
              child: SizedBox(
                height: 56,
                width: double.infinity,
                child: CustomPaint(
                  painter: _CoveragePainter(
                    played: widget.played,
                    extentMs: extent,
                    playheadMs: widget.playheadMs,
                    selectedMs: widget.selectedMs,
                    focused: _focus.hasFocus,
                    playedColor: cs.primary,
                    emptyColor: cs.surfaceContainerHighest,
                    hatchColor: cs.outlineVariant,
                    markerColor: cs.onSurface,
                    selectionColor: cs.tertiary,
                    surfaceColor: cs.surface,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CoveragePainter extends CustomPainter {
  final List<CoverageInterval> played;
  final int extentMs;
  final int? playheadMs;
  final int? selectedMs;
  final bool focused;
  final Color playedColor;
  final Color emptyColor;
  final Color hatchColor;
  final Color markerColor;
  final Color selectionColor;
  final Color surfaceColor;

  const _CoveragePainter({
    required this.played,
    required this.extentMs,
    required this.playedColor,
    required this.emptyColor,
    required this.hatchColor,
    required this.markerColor,
    required this.selectionColor,
    required this.surfaceColor,
    this.playheadMs,
    this.selectedMs,
    this.focused = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      8,
      size.height / 2 - 6,
      math.max(0.0, size.width - 16),
      12,
    );
    final rounded = RRect.fromRectAndRadius(rect, const Radius.circular(5));
    canvas.save();
    canvas.clipRRect(rounded);
    canvas.drawRect(rect, Paint()..color = emptyColor);
    final hatch = Paint()
      ..color = hatchColor
      ..strokeWidth = 1;
    for (var x = rect.left - 12; x < rect.right + 12; x += 7) {
      canvas.drawLine(Offset(x, rect.bottom), Offset(x + 12, rect.top), hatch);
    }
    double xAt(int position) =>
        rect.left + (position / extentMs).clamp(0.0, 1.0) * rect.width;
    if (extentMs > 0) {
      for (final interval in played) {
        if (interval.endMs <= 0 || interval.startMs >= extentMs) continue;
        final start = xAt(interval.startMs);
        final end = xAt(interval.endMs);
        canvas.drawRect(
          Rect.fromLTRB(start, rect.top, end, rect.bottom),
          Paint()..color = playedColor,
        );
      }
    }
    canvas.restore();
    if (extentMs > 0 &&
        playheadMs != null &&
        playheadMs! >= 0 &&
        playheadMs! <= extentMs) {
      final x = xAt(playheadMs!);
      final marker = Paint()
        ..color = markerColor
        ..strokeWidth = 2;
      canvas.drawLine(
        Offset(x, rect.top - 5),
        Offset(x, rect.bottom + 5),
        marker,
      );
      canvas.drawPath(
        Path()
          ..moveTo(x - 4, rect.top - 9)
          ..lineTo(x + 4, rect.top - 9)
          ..lineTo(x, rect.top - 4)
          ..close(),
        marker,
      );
    }
    if (extentMs > 0 && selectedMs != null) {
      final point = Offset(xAt(selectedMs!), rect.center.dy);
      canvas.drawCircle(point, 7, Paint()..color = surfaceColor);
      canvas.drawCircle(
        point,
        6,
        Paint()
          ..color = selectionColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5,
      );
    }
    if (focused) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(1, 4, math.max(0.0, size.width - 2), size.height - 8),
          const Radius.circular(8),
        ),
        Paint()
          ..color = selectionColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CoveragePainter oldDelegate) =>
      oldDelegate.played != played ||
      oldDelegate.extentMs != extentMs ||
      oldDelegate.playheadMs != playheadMs ||
      oldDelegate.selectedMs != selectedMs ||
      oldDelegate.focused != focused ||
      oldDelegate.playedColor != playedColor ||
      oldDelegate.emptyColor != emptyColor ||
      oldDelegate.hatchColor != hatchColor ||
      oldDelegate.markerColor != markerColor ||
      oldDelegate.selectionColor != selectionColor ||
      oldDelegate.surfaceColor != surfaceColor;
}

class _CoverageLegend extends StatelessWidget {
  const _CoverageLegend();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget item(Widget mark, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(child: mark),
        const SizedBox(width: 6),
        Flexible(
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        item(Container(width: 16, height: 10, color: cs.primary), 'Played'),
        item(
          SizedBox(
            width: 32,
            height: 16,
            child: CustomPaint(
              painter: _CoveragePainter(
                played: const [],
                extentMs: 1,
                playedColor: cs.primary,
                emptyColor: cs.surfaceContainerHighest,
                hatchColor: cs.outlineVariant,
                markerColor: cs.onSurface,
                selectionColor: cs.tertiary,
                surfaceColor: cs.surface,
              ),
            ),
          ),
          'No playback recorded',
        ),
        item(
          Icon(Icons.arrow_drop_down, color: cs.onSurface, size: 20),
          'Current position',
        ),
      ],
    );
  }
}
