import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/providers.dart';
import '../services/db/app_database.dart';
import '../utils/format.dart';
import '../widgets/chapter_tile.dart';
import '../widgets/chapter_progress.dart';
import '../widgets/waveform_view.dart';
import '../widgets/sleep_timer_sheet.dart';
import '../widgets/speed_sheet.dart';
import '../widgets/chapter_list_sheet.dart';
import '../widgets/book_details_sheet.dart';
import '../widgets/book_preferences_sheet.dart';
import '../widgets/queue_sheet.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final String bookId;
  const PlayerScreen({super.key, required this.bookId});
  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  bool _showChapters = false;
  bool _ready = false;
  String? _pendingNavigation;

  Future<void> _openRequestedBook() async {
    if (!mounted) return;
    final requested = widget.bookId;
    final svc = ref.read(playbackProvider);
    try {
      if (svc.currentBookId != requested) await svc.loadBook(requested);
      if (mounted && widget.bookId == requested) setState(() => _ready = true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Load failed: $e')));
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openRequestedBook());
  }

  @override
  void didUpdateWidget(covariant PlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookId != widget.bookId) {
      _ready = false;
      _pendingNavigation = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _openRequestedBook());
    }
  }

  @override
  Widget build(BuildContext context) {
    final svc = ref.watch(playbackProvider);
    final bookAsync = ref.watch(bookProvider(widget.bookId));
    final chaptersAsync = ref.watch(chaptersProvider(widget.bookId));
    final bookmarksAsync = ref.watch(bookmarksProvider(widget.bookId));

    return bookAsync.when(
      data: (book) {
        if (book == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Not found')),
            body: const Center(child: Text('Book not found')),
          );
        }
        return StreamBuilder(
          stream: svc.stateStream,
          initialData: svc.state,
          builder: (ctx, snap) {
            final active = svc.currentBookId;
            if (_ready && active != null && active != widget.bookId && _pendingNavigation != active) {
              _pendingNavigation = active;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _pendingNavigation = null;
                if (context.mounted && svc.currentBookId == active) context.replace('/player/$active');
              });
            }
            final st = snap.data ?? svc.state;
            final wholeDuration = svc.bookDuration;
            final displayDuration = wholeDuration ?? st.duration;
            final displayPosition = wholeDuration == null
                ? st.position
                : svc.bookPosition;
            final remaining = Duration(
              milliseconds:
                  ((displayDuration.inMilliseconds -
                                  displayPosition.inMilliseconds)
                              .clamp(0, displayDuration.inMilliseconds) /
                          st.speed)
                      .ceil(),
            );
            final displayProgress = displayDuration.inMilliseconds == 0
                ? 0.0
                : (displayPosition.inMilliseconds /
                          displayDuration.inMilliseconds)
                      .clamp(0.0, 1.0);
            final hasCover = book.coverPath.isNotEmpty;
            final cs = Theme.of(context).colorScheme;
            final chapters = chaptersAsync.value ?? <Chapter>[];
            final currentChapter = _currentChapter(chapters, svc.bookPosition);
            final coverSize = (MediaQuery.sizeOf(context).height * 0.20).clamp(
              64.0,
              160.0,
            );

            return Focus(
              autofocus: true,
              onKeyEvent: (node, event) {
                if (event is! KeyDownEvent) return KeyEventResult.ignored;
                final focused = FocusManager.instance.primaryFocus?.context;
                if (focused?.findAncestorWidgetOfExactType<EditableText>() !=
                    null) {
                  return KeyEventResult.ignored;
                }
                Future<void>? command;
                final key = event.logicalKey;
                if (key == LogicalKeyboardKey.space) {
                  command = st.isPlaying ? svc.pause() : svc.play();
                }
                if (key == LogicalKeyboardKey.arrowLeft) {
                  command = HardwareKeyboard.instance.isShiftPressed
                      ? svc.previousChapter()
                      : svc.skipBack();
                }
                if (key == LogicalKeyboardKey.arrowRight) {
                  command = HardwareKeyboard.instance.isShiftPressed
                      ? svc.nextChapter()
                      : svc.skipForward();
                }
                if (key == LogicalKeyboardKey.keyB &&
                    !HardwareKeyboard.instance.isMetaPressed &&
                    !HardwareKeyboard.instance.isControlPressed) {
                  command = svc.addManualBookmark().then<void>((_) {});
                }
                if (command == null) return KeyEventResult.ignored;
                command.catchError((Object e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(e.toString())));
                  }
                });
                return KeyEventResult.handled;
              },
              child: Scaffold(
                appBar: AppBar(
                  title: Text(
                    book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.bedtime_outlined),
                      tooltip: 'Sleep timer',
                      onPressed: () => showSleepTimerSheet(context, svc),
                    ),
                    IconButton(
                      icon: const Icon(Icons.speed),
                      tooltip: 'Speed',
                      onPressed: () => showSpeedSheet(context, svc),
                    ),
                    IconButton(
                      icon: const Icon(Icons.bookmark_border),
                      tooltip: 'Bookmarks',
                      onPressed: () =>
                          context.push('/bookmarks/${widget.bookId}'),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'shortcuts') {
                          showDialog<void>(
                            context: context,
                            builder: (_) => const AlertDialog(
                              title: Text('Keyboard shortcuts'),
                              content: Text(
                                'Space: play / pause\nLeft / right: skip backward / forward\nShift + left / right: previous / next chapter\nB: add bookmark',
                              ),
                            ),
                          );
                          return;
                        }
                        if (v == 'edit') {
                          await showBookDetails(context, book);
                          return;
                        }
                        if (v == 'preferences') {
                          await showBookPreferences(context, book);
                          return;
                        }
                        if (v == 'queue') {
                          await showQueue(context);
                          return;
                        }
                        if (v == 'refreshChapters') {
                          try {
                            final refreshed = await svc.refreshChapters(
                              widget.bookId,
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    refreshed
                                        ? 'Chapters updated'
                                        : 'No embedded chapters found',
                                  ),
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Could not reload chapters: $e',
                                  ),
                                ),
                              );
                            }
                          }
                        }
                        if (!context.mounted) return;
                        if (v == 'chapters') {
                          setState(() => _showChapters = !_showChapters);
                        }
                        if (v == 'chaptersSheet') {
                          showChapterListSheet(
                            context,
                            chapters: chapters,
                            position: st.position,
                            svc: svc,
                          );
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'shortcuts',
                          child: Text('Keyboard shortcuts'),
                        ),
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit book details'),
                        ),
                        const PopupMenuItem(
                          value: 'preferences',
                          child: Text('Playback for this book'),
                        ),
                        const PopupMenuItem(
                          value: 'queue',
                          child: Text('Up next'),
                        ),
                        const PopupMenuItem(
                          value: 'refreshChapters',
                          child: Text('Reload embedded chapters'),
                        ),
                        PopupMenuItem(
                          value: 'chapters',
                          child: Text(
                            _showChapters
                                ? 'Hide chapters'
                                : 'Show inline chapters',
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'chaptersSheet',
                          child: Text('Open chapter list'),
                        ),
                      ],
                    ),
                  ],
                ),
                bottomNavigationBar: Material(
                  color: cs.surfaceContainerLow,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Chapter progress with markers + slider
                          if (chapters.isNotEmpty &&
                              wholeDuration != null &&
                              wholeDuration != Duration.zero)
                            ChapterProgressBar(
                              position: displayPosition,
                              duration: displayDuration,
                              chapters: chapters,
                              onSeek: (d) => svc.seekBook(d),
                            )
                          else
                            Slider(
                              min: 0,
                              max: (st.duration.inMilliseconds.toDouble() > 0
                                  ? st.duration.inMilliseconds.toDouble()
                                  : 1),
                              value: st.position.inMilliseconds
                                  .clamp(0, st.duration.inMilliseconds)
                                  .toDouble(),
                              onChanged: (v) =>
                                  svc.seek(Duration(milliseconds: v.round())),
                            ),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                formatDuration(displayPosition),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                '${(displayProgress * 100).toStringAsFixed(0)}% • ${formatDuration(remaining)} left',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Transport controls
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.skip_previous),
                                iconSize: 36,
                                tooltip: 'Previous chapter',
                                onPressed: () => svc.previousChapter(),
                              ),
                              IconButton(
                                icon: const Icon(Icons.replay),
                                iconSize: 36,
                                tooltip: '-${svc.seekSeconds}s',
                                onPressed: () => svc.skipBack(),
                              ),
                              FilledButton(
                                key: const ValueKey('player-play-pause'),
                                style: FilledButton.styleFrom(
                                  shape: const CircleBorder(),
                                  padding: const EdgeInsets.all(18),
                                ),
                                onPressed: () =>
                                    st.isPlaying ? svc.pause() : svc.play(),
                                child: Icon(
                                  st.isPlaying ? Icons.pause : Icons.play_arrow,
                                  semanticLabel: st.isPlaying ? 'Pause' : 'Play',
                                  size: 36,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.forward),
                                iconSize: 36,
                                tooltip: '+${svc.seekSeconds}s',
                                onPressed: () => svc.skipForward(),
                              ),
                              IconButton(
                                icon: const Icon(Icons.skip_next),
                                iconSize: 36,
                                tooltip: 'Next chapter',
                                onPressed: () => svc.nextChapter(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                ),
                body: Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            // Cover with waveform overlay
                            SizedBox(
                              width: coverSize,
                              height: coverSize,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(18),
                                  color: cs.primaryContainer,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.12,
                                      ),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6),
                                    ),
                                  ],
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    hasCover
                                        ? Image.file(
                                            File(book.coverPath),
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, _, _) => Center(
                                              child: Icon(
                                                Icons.menu_book,
                                                size: 96,
                                                color: cs.onPrimaryContainer,
                                              ),
                                            ),
                                          )
                                        : Center(
                                            child: Icon(
                                              Icons.menu_book,
                                              size: 96,
                                              color: cs.onPrimaryContainer,
                                            ),
                                          ),
                                    // playback indicator overlay
                                    Positioned(
                                      right: 12,
                                      top: 12,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(
                                            alpha: 0.55,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              st.isPlaying
                                                  ? Icons.graphic_eq
                                                  : Icons.pause,
                                              size: 14,
                                              color: Colors.white,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              st.isPlaying
                                                  ? 'Playing'
                                                  : 'Paused',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              book.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              book.author,
                              style: TextStyle(
                                color: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.color
                                    ?.withValues(alpha: 0.7),
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Current chapter
                            if (chapters.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.secondaryContainer,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.menu_book_outlined,
                                      size: 14,
                                      color: cs.onSecondaryContainer,
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        currentChapter?.title ?? 'Chapter',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: cs.onSecondaryContainer,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 6),

                            // Sleep timer chips
                            if (svc.sleepRemaining != Duration.zero ||
                                svc.isWaitingForChapterEnd)
                              Wrap(
                                spacing: 6,
                                children: [
                                  if (svc.sleepRemaining != Duration.zero &&
                                      !svc.isWaitingForChapterEnd)
                                    Chip(
                                      label: Text(
                                        'Sleep in ${formatDuration(svc.sleepRemaining)}',
                                      ),
                                      onDeleted: () => svc.cancelSleepTimer(),
                                      deleteIcon: const Icon(
                                        Icons.close,
                                        size: 16,
                                      ),
                                    ),
                                  if (svc.isWaitingForChapterEnd)
                                    Chip(
                                      label: const Text(
                                        'Sleep: end of chapter',
                                      ),
                                      onDeleted: () => svc.cancelSleepTimer(),
                                      deleteIcon: const Icon(
                                        Icons.close,
                                        size: 16,
                                      ),
                                    ),
                                  if (svc.sleepEndOfChapter &&
                                      svc.sleepRemaining != Duration.zero &&
                                      !svc.isWaitingForChapterEnd)
                                    Chip(
                                      label: Text(
                                        'Sleep: ${formatDuration(svc.sleepRemaining)} → end of chapter',
                                      ),
                                      onDeleted: () => svc.cancelSleepTimer(),
                                      deleteIcon: const Icon(
                                        Icons.close,
                                        size: 16,
                                      ),
                                    ),
                                ],
                              ),

                            const SizedBox(height: 12),

                            // Waveform view
                            WaveformView(
                              isPlaying: st.isPlaying,
                              position: st.position,
                              duration: st.duration,
                              height: 40,
                            ),
                            const SizedBox(height: 8),

                            // Quick chapter jump row
                            if (chapters.isNotEmpty)
                              SizedBox(
                                height: 36,
                                child: ListView.separated(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: chapters.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(width: 8),
                                  itemBuilder: (ctx, i) {
                                    final ch = chapters[i];
                                    final isCur = currentChapter?.id == ch.id;
                                    return ChoiceChip(
                                      key: ValueKey('chapter-${ch.id}'),
                                      showCheckmark: false,
                                      label: Text(
                                        ch.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      selected: isCur,
                                      onSelected: (_) async =>
                                          svc.seekChapter(ch),
                                      avatar: isCur
                                          ? Icon(
                                              Icons.play_arrow,
                                              size: 14,
                                              color: cs.primary,
                                            )
                                          : null,
                                    );
                                  },
                                ),
                              ),
                            if (chapters.isNotEmpty)
                              TextButton.icon(
                                icon: const Icon(Icons.list, size: 16),
                                label: const Text('Show all chapters'),
                                onPressed: () => showChapterListSheet(
                                  context,
                                  chapters: chapters,
                                  position: st.position,
                                  svc: svc,
                                ),
                              ),

                            const SizedBox(height: 8),

                            // Speed control row
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.speed, size: 18),
                                    const SizedBox(width: 8),
                                    Text(
                                      '${st.speed.toStringAsFixed(2)}×',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Wrap(
                                        spacing: 6,
                                        children: [0.8, 1.0, 1.25, 1.5, 2.0]
                                            .map((s) {
                                              final sel =
                                                  (st.speed - s).abs() < 0.02;
                                              return ChoiceChip(
                                                key: ValueKey('speed-$s'),
                                                showCheckmark: false,
                                                label: Text(
                                                  '$s×',
                                                  style: const TextStyle(
                                                    fontSize: 11,
                                                  ),
                                                ),
                                                selected: sel,
                                                visualDensity:
                                                    VisualDensity.compact,
                                                materialTapTargetSize:
                                                    MaterialTapTargetSize
                                                        .shrinkWrap,
                                                onSelected: (_) =>
                                                    svc.setSpeed(s),
                                              );
                                            })
                                            .toList(),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.tune, size: 18),
                                      tooltip: 'More speeds',
                                      onPressed: () =>
                                          showSpeedSheet(context, svc),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 8),

                            // Bookmarks preview
                            bookmarksAsync.when(
                              data: (bms) {
                                if (bms.isEmpty) return const SizedBox.shrink();
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        const Text(
                                          'Bookmarks',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const Spacer(),
                                        TextButton(
                                          onPressed: () => context.push(
                                            '/bookmarks/${widget.bookId}',
                                          ),
                                          child: const Text('View all'),
                                        ),
                                      ],
                                    ),
                                    ...bms
                                        .take(3)
                                        .map(
                                          (bm) => ListTile(
                                            dense: true,
                                            leading: Icon(
                                              bm.kind == 'auto'
                                                  ? Icons.bookmark_border
                                                  : Icons.bookmark,
                                              size: 18,
                                            ),
                                            title: Text(bm.title, maxLines: 1),
                                            subtitle: Text(
                                              formatDuration(
                                                Duration(
                                                  milliseconds: bm.positionMs,
                                                ),
                                              ),
                                            ),
                                            onTap: () async =>
                                                svc.seekBookmark(bm),
                                          ),
                                        ),
                                  ],
                                );
                              },
                              loading: () => const SizedBox.shrink(),
                              error: (_, _) => const SizedBox.shrink(),
                            ),
                            const SizedBox(height: 12),

                            FilledButton.icon(
                              icon: const Icon(Icons.bookmark_add),
                              label: const Text('Add bookmark'),
                              onPressed: () async {
                                final titleCtrl = TextEditingController(
                                  text:
                                      'Bookmark @ ${formatDuration(displayPosition)}',
                                );
                                final noteCtrl = TextEditingController();
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('New bookmark'),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        TextField(
                                          controller: titleCtrl,
                                          decoration: const InputDecoration(
                                            labelText: 'Title',
                                          ),
                                        ),
                                        TextField(
                                          controller: noteCtrl,
                                          decoration: const InputDecoration(
                                            labelText: 'Note (optional)',
                                          ),
                                        ),
                                      ],
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, false),
                                        child: const Text('Cancel'),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(ctx, true),
                                        child: const Text('Save'),
                                      ),
                                    ],
                                  ),
                                );
                                if (ok == true) {
                                  await svc.addManualBookmark(
                                    title: titleCtrl.text,
                                    note: noteCtrl.text.isEmpty
                                        ? null
                                        : noteCtrl.text,
                                  );
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Bookmark saved'),
                                      ),
                                    );
                                  }
                                }
                              },
                            ),

                            if (_showChapters) ...[
                              const Divider(height: 24),
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Chapters',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                              ...chapters.map(
                                (ch) => ChapterTile(
                                  chapter: ch,
                                  isCurrent: currentChapter?.id == ch.id,
                                  onTap: () async => svc.seekChapter(ch),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
      loading: () => Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Error: $e')),
      ),
    );
  }

  Chapter? _currentChapter(List<Chapter> chapters, Duration position) {
    for (final chapter in chapters) {
      if (position.inMilliseconds >= chapter.startMs &&
          position.inMilliseconds < chapter.endMs) {
        return chapter;
      }
    }
    return chapters.isEmpty ? null : chapters.last;
  }
}
