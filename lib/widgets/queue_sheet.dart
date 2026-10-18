import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../services/db/app_database.dart';

Future<void> showQueue(BuildContext context) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => const _QueueSheet(),
);

class _QueueSheet extends ConsumerWidget {
  const _QueueSheet();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);
    final svc = ref.watch(playbackProvider);
    Future<void> act(Future<void> Function() action) async {
      try {
        await action();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.toString())));
        }
      }
    }

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    'Up next',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => act(svc.playNextQueued),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Play next'),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Books play in this order when the current book finishes. Sleep timers stop automatic continuation.',
              ),
            ),
            Expanded(
              child: StreamBuilder<List<PlaybackQueueData>>(
                stream: db.watchQueue(),
                builder: (context, snapshot) {
                  final queue = snapshot.data ?? [];
                  if (queue.isEmpty) {
                    return const Center(
                      child: Text(
                        'Queue is empty. Add books from the library menu.',
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: queue.length,
                    itemBuilder: (context, index) {
                      final entry = queue[index];
                      final book = ref.watch(bookProvider(entry.bookId)).value;
                      return ListTile(
                        title: Text(book?.title ?? 'Loading…', maxLines: 2),
                        subtitle: Text(book?.author ?? ''),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Move up',
                              icon: const Icon(Icons.arrow_upward),
                              onPressed: index == 0
                                  ? null
                                  : () => act(
                                      () => svc.enqueue(
                                        entry.bookId,
                                        position: index - 1,
                                      ),
                                    ),
                            ),
                            IconButton(
                              tooltip: 'Move down',
                              icon: const Icon(Icons.arrow_downward),
                              onPressed: index == queue.length - 1
                                  ? null
                                  : () => act(
                                      () => svc.enqueue(
                                        entry.bookId,
                                        position: index + 1,
                                      ),
                                    ),
                            ),
                            IconButton(
                              tooltip: 'Remove from queue',
                              icon: const Icon(Icons.close),
                              onPressed: () =>
                                  act(() => svc.removeFromQueue(entry.bookId)),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
