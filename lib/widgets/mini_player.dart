import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../utils/format.dart';
import 'package:go_router/go_router.dart';

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
            return Material(
              elevation: 8,
              color: Theme.of(context).colorScheme.surfaceContainer,
              child: InkWell(
                onTap: ()=> context.push('/player/$bookId'),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(value: st.progress, minHeight: 2),
                    ListTile(
                      dense: true,
                      title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Text('${formatDuration(st.position)} / ${formatDuration(st.duration)}', style: const TextStyle(fontSize: 11)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(icon: Icon(st.isPlaying ? Icons.pause : Icons.play_arrow), onPressed: ()=> st.isPlaying ? svc.pause() : svc.play()),
                          IconButton(icon: const Icon(Icons.close, size: 18), onPressed: ()=> svc.stop()),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          loading: ()=> const SizedBox.shrink(),
          error: (_,__)=> const SizedBox.shrink(),
        );
      },
    );
  }
}
