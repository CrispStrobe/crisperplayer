import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/providers.dart';
import '../utils/format.dart';
import 'waveform_view.dart';

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.watch(playbackProvider);
    final bookId = svc.currentBookId;
    if (bookId == null) return const SizedBox.shrink();

    return StreamBuilder(
      stream: svc.stateStream,
      initialData: svc.state,
      builder: (ctx, snap) {
        final st = snap.data ?? svc.state;
        final duration = svc.bookDuration ?? st.duration;
        final position = svc.bookDuration == null
            ? st.position
            : svc.bookPosition;
        final progress = duration.inMilliseconds > 0
            ? (position.inMilliseconds / duration.inMilliseconds).clamp(
                0.0,
                1.0,
              )
            : 0.0;
        final bookAsync = ref.watch(bookProvider(bookId));
        return bookAsync.when(
          data: (book) {
            if (book == null) return const SizedBox.shrink();
            final cs = Theme.of(context).colorScheme;
            return Material(
              elevation: 8,
              color: cs.surfaceContainer,
              child: InkWell(
                onTap: () => context.push('/player/$bookId'),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(
                      key: const ValueKey('mini-book-progress'),
                      value: progress,
                      minHeight: 3,
                      backgroundColor: cs.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation(cs.primary),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: cs.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: book.coverPath.isNotEmpty
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(
                                      File(book.coverPath),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Icon(
                                        Icons.menu_book,
                                        size: 20,
                                        color: cs.onPrimaryContainer,
                                      ),
                                    ),
                                  )
                                : Icon(
                                    Icons.menu_book,
                                    size: 20,
                                    color: cs.onPrimaryContainer,
                                  ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  book.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        '${formatDuration(position)} / ${formatDuration(duration)}',
                                        semanticsLabel:
                                            '${formatSpokenDuration(position)} of ${formatSpokenDuration(duration)}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                    if (MediaQuery.textScalerOf(
                                          context,
                                        ).scale(11) <=
                                        16) ...[
                                      const SizedBox(width: 8),
                                      MiniWaveform(progress: progress),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: st.isPlaying ? 'Pause' : 'Play',
                            icon: Icon(
                              st.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                            ),
                            onPressed: () =>
                                st.isPlaying ? svc.pause() : svc.play(),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            tooltip: 'Close player',
                            onPressed: () => svc.unload(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
        );
      },
    );
  }
}
