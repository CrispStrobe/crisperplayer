import 'dart:async';

import 'package:flutter/material.dart';

import '../models/playback_state.dart';
import '../models/return_trail.dart';
import '../services/audio/playback_service.dart';
import '../utils/format.dart';

Future<void> showReturnTrailSheet(
  BuildContext context,
  PlaybackService playback, {
  required String bookId,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => ReturnTrailSheet(playback: playback, bookId: bookId),
);

/// The player keeps this entry point visible while a trail runs, even when its
/// sheet is closed. All playback continues through the production coordinator.
class ReturnTrailCard extends StatelessWidget {
  final PlaybackService playback;
  final String bookId;

  const ReturnTrailCard({
    super.key,
    required this.playback,
    required this.bookId,
  });

  @override
  Widget build(BuildContext context) => StreamBuilder<PlaybackState>(
    stream: playback.stateStream,
    initialData: playback.state,
    builder: (context, _) {
      final plan = playback.returnTrailPlan;
      final active =
          playback.isReturnTrailActive &&
          plan != null &&
          plan.anchor.bookId == bookId;
      final sameBook = playback.currentBookId == bookId;
      final cs = Theme.of(context).colorScheme;
      return Card.filled(
        key: const ValueKey('return-trail-card'),
        margin: EdgeInsets.zero,
        color: active ? cs.secondaryContainer : cs.surfaceContainerLow,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: sameBook
              ? () => showReturnTrailSheet(context, playback, bookId: bookId)
              : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  active ? Icons.headphones : Icons.route_outlined,
                  color: active ? cs.onSecondaryContainer : cs.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Return Trail',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: active ? cs.onSecondaryContainer : null,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        active
                            ? '${playback.state.isPlaying ? 'Catching up' : 'Trail paused'} · passage ${playback.returnTrailClipIndex + 1} of ${plan.clips.length}'
                            : 'Get back into the story without losing your place.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (active) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Your place is saved · open trail to return',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class ReturnTrailSheet extends StatefulWidget {
  final PlaybackService playback;
  final String bookId;

  const ReturnTrailSheet({
    super.key,
    required this.playback,
    required this.bookId,
  });

  @override
  State<ReturnTrailSheet> createState() => _ReturnTrailSheetState();
}

class _ReturnTrailSheetState extends State<ReturnTrailSheet> {
  late final StreamSubscription<PlaybackState> _subscription;
  Duration _budget = const Duration(seconds: 60);
  ReturnTrailPlan? _preview;
  bool _loading = false;
  bool _busy = false;
  bool _wasActive = false;
  double _lastSpeed = 1;
  int _previewRequest = 0;
  String? _error;
  String? _completion;

  PlaybackService get _playback => widget.playback;
  bool get _sameBook => _playback.currentBookId == widget.bookId;
  bool get _active =>
      _playback.isReturnTrailActive &&
      _playback.returnTrailPlan?.anchor.bookId == widget.bookId;

  @override
  void initState() {
    super.initState();
    _wasActive = _active;
    _lastSpeed = _playback.state.speed;
    if (_active) _budget = _playback.returnTrailPlan!.requestedDuration;
    _subscription = _playback.stateStream.listen((state) {
      if (!mounted) return;
      final active = _active;
      final ended = _wasActive && !active && _sameBook;
      final speedChanged = state.speed != _lastSpeed;
      _lastSpeed = state.speed;
      _wasActive = active;
      setState(() {
        if (ended && !_busy && _completion == null) {
          _completion = 'Return Trail finished.';
        }
      });
      if (_sameBook && !active && (ended || speedChanged)) {
        unawaited(_loadPreview());
      }
    });
    if (!_active) unawaited(_loadPreview());
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  Future<void> _loadPreview() async {
    if (!mounted || !_sameBook || _active) return;
    final request = ++_previewRequest;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final plan = await _playback.previewReturnTrail(
        budget: _budget,
        expectedBookId: widget.bookId,
      );
      if (mounted && request == _previewRequest && _sameBook && !_active) {
        setState(() => _preview = plan);
      }
    } catch (error) {
      if (mounted && request == _previewRequest) {
        setState(() {
          _preview = null;
          _error = 'Could not prepare your trail: $error';
        });
      }
    } finally {
      if (mounted && request == _previewRequest) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _act(
    Future<void> Function() action, {
    bool activeOnly = false,
    String? completion,
  }) async {
    if (_busy) return;
    if (!_sameBook) {
      setState(
        () => _error = 'The playing book changed. Open its Return Trail.',
      );
      return;
    }
    if (activeOnly && !_active) {
      unawaited(_loadPreview());
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _completion = null;
    });
    final startedActive = _active;
    var succeeded = false;
    try {
      await action();
      succeeded = true;
      if (mounted && _sameBook) {
        setState(() {
          _completion =
              completion ??
              (startedActive && !_active
                  ? 'Back at your saved place. Playback is paused.'
                  : null);
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Return Trail: $error');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (!_active && succeeded) unawaited(_loadPreview());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final active = _active;
    final plan = active ? _playback.returnTrailPlan : _preview;
    final state = _playback.state;
    final clipIndex = _playback.returnTrailClipIndex;
    final estimate = plan == null
        ? Duration.zero
        : Duration(
            milliseconds: (plan.mediaDuration.inMilliseconds / state.speed)
                .ceil(),
          );
    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .82,
        child: SingleChildScrollView(
          key: const ValueKey('return-trail-scroll'),
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.route_outlined, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Return Trail', style: text.titleLarge)),
                  IconButton(
                    tooltip: 'Close Return Trail',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Get back into the story without losing your place.',
                style: text.bodyLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Revisit passages you played, in the original narration. Your audio is replayed locally.',
                style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
              if (!_sameBook) ...[
                const SizedBox(height: 20),
                const _TrailNotice(
                  icon: Icons.info_outline,
                  message:
                      'The playing book changed. Close this sheet and open Return Trail for that book.',
                ),
              ] else ...[
                if (_completion != null) ...[
                  const SizedBox(height: 16),
                  _TrailNotice(
                    icon: Icons.check_circle_outline,
                    message: _completion!,
                  ),
                ],
                const SizedBox(height: 20),
                if (!active) ...[
                  Text('Time for catching up', style: text.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final seconds in [30, 60, 120])
                        ChoiceChip(
                          key: ValueKey('return-trail-budget-$seconds'),
                          label: Text(
                            '$seconds sec',
                            semanticsLabel: '$seconds seconds of listening',
                          ),
                          selected: _budget.inSeconds == seconds,
                          onSelected: _busy
                              ? null
                              : (_) {
                                  setState(
                                    () => _budget = Duration(seconds: seconds),
                                  );
                                  unawaited(_loadPreview());
                                },
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                if (_error != null) ...[
                  Semantics(
                    liveRegion: true,
                    child: Text(_error!, style: TextStyle(color: cs.error)),
                  ),
                  const SizedBox(height: 12),
                  if (!active)
                    OutlinedButton.icon(
                      onPressed: _loading || _busy ? null : _loadPreview,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                ],
                if (_loading && !active)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: LinearProgressIndicator(
                      semanticsLabel: 'Preparing Return Trail',
                    ),
                  )
                else if (plan != null && plan.clips.isEmpty) ...[
                  const _TrailNotice(
                    icon: Icons.headphones_outlined,
                    message:
                        'Your trail starts with your next listen. Play a few passages, then come back here. Recording starts with this version; older listening history is not used to guess what you heard.',
                  ),
                ] else if (plan != null) ...[
                  _TrailNotice(
                    icon: Icons.bookmark_added_outlined,
                    message:
                        '${active ? 'Your protected place' : 'Return point'}\n${safeBasename(plan.anchor.filePath)} · ${formatDuration(Duration(milliseconds: plan.anchor.positionMs))}',
                    noticeKey: const ValueKey('return-trail-anchor'),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    active
                        ? '${state.isPlaying ? 'Catching up' : 'Trail paused'} · passage ${clipIndex + 1} of ${plan.clips.length}'
                        : '${plan.clips.length} ${plan.clips.length == 1 ? 'passage' : 'passages'} to revisit',
                    key: const ValueKey('return-trail-status'),
                    style: text.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'About ${formatDuration(estimate)} listening at ${state.speed}× · ${formatDuration(plan.mediaDuration)} of original audio',
                    key: const ValueKey('return-trail-duration'),
                    style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  if (active) ...[
                    FilledButton.icon(
                      key: const ValueKey('return-trail-return'),
                      onPressed: _busy
                          ? null
                          : () => _act(
                              () => _playback.finishReturnTrail(),
                              activeOnly: true,
                              completion:
                                  'Back at your saved place. Playback is paused.',
                            ),
                      icon: const Icon(Icons.keyboard_return),
                      label: const Text('Return to my place'),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          key: const ValueKey('return-trail-pause'),
                          onPressed: _busy
                              ? null
                              : () => _act(
                                  state.isPlaying
                                      ? _playback.pause
                                      : _playback.play,
                                  activeOnly: true,
                                ),
                          icon: Icon(
                            state.isPlaying ? Icons.pause : Icons.play_arrow,
                          ),
                          label: Text(
                            state.isPlaying ? 'Pause trail' : 'Resume trail',
                          ),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey('return-trail-next'),
                          onPressed: _busy
                              ? null
                              : () => _act(
                                  _playback.nextReturnTrailClip,
                                  activeOnly: true,
                                ),
                          icon: const Icon(Icons.skip_next),
                          label: Text(
                            clipIndex + 1 < plan.clips.length
                                ? 'Next passage'
                                : 'Finish trail',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      key: const ValueKey('return-trail-continue'),
                      onPressed: _busy
                          ? null
                          : () => _act(
                              () => _playback.finishReturnTrail(
                                continueHere: true,
                              ),
                              activeOnly: true,
                              completion: 'Continuing from this passage.',
                            ),
                      icon: const Icon(Icons.play_circle_outline),
                      label: const Text('Continue from here'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'When the trail ends, you return to your saved place, paused. Choose Continue from here to make this passage your new position.',
                      style: text.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ] else ...[
                    FilledButton.icon(
                      key: const ValueKey('return-trail-start'),
                      onPressed: _busy
                          ? null
                          : () => _act(
                              () => _playback.startReturnTrail(
                                budget: _budget,
                                expectedBookId: widget.bookId,
                              ),
                            ),
                      icon: const Icon(Icons.headphones),
                      label: const Text('Start Return Trail'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your place is saved before the first passage plays. The trail returns there and pauses when it ends.',
                      style: text.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Text('Your passages', style: text.titleSmall),
                  const SizedBox(height: 8),
                  for (var index = 0; index < plan.clips.length; index++)
                    _PassageTile(
                      clip: plan.clips[index],
                      number: index + 1,
                      current: active && index == clipIndex,
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TrailNotice extends StatelessWidget {
  final IconData icon;
  final String message;
  final Key? noticeKey;

  const _TrailNotice({
    required this.icon,
    required this.message,
    this.noticeKey,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: noticeKey,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: cs.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _PassageTile extends StatelessWidget {
  final TrailClip clip;
  final int number;
  final bool current;

  const _PassageTile({
    required this.clip,
    required this.number,
    required this.current,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      selected: current,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: current ? cs.secondaryContainer : cs.surface,
          border: Border.all(color: current ? cs.secondary : cs.outlineVariant),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: current
                  ? cs.secondary
                  : cs.surfaceContainerHighest,
              child: Text(
                '$number',
                style: text.labelMedium?.copyWith(
                  color: current ? cs.onSecondary : cs.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(clip.title, style: text.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    'Track ${clip.trackIndex + 1} · ${formatDuration(Duration(milliseconds: clip.startMs))}–${formatDuration(Duration(milliseconds: clip.endMs))}',
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    clip.reason,
                    style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
