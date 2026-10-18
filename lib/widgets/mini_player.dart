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
                      value: st.progress,
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
                            child: Icon(Icons.menu_book,
                                size: 20, color: cs.onPrimaryContainer),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(book.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13)),
                                const SizedBox(height: 2),
                                Row(children: [
                                  Text(
                                      '${formatDuration(st.position)} / ${formatDuration(st.duration)}',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: cs.onSurfaceVariant)),
                                  const SizedBox(width: 8),
                                  MiniWaveform(progress: st.progress),
                                ]),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(st.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded),
                            onPressed: () =>
                                st.isPlaying ? svc.pause() : svc.play(),
                            visualDensity: VisualDensity.compact,
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => svc.stop(),
                            visualDensity: VisualDensity.compact,
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
          error: (_, __) => const SizedBox.shrink(),
        );
      },
    );
  }
}
