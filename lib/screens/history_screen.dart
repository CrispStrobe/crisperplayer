import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/providers.dart';
import '../utils/format.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final histAsync = ref.watch(historyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Listening history')),
      body: histAsync.when(
        data: (entries) {
          if (entries.isEmpty) {
            return const Center(
                child: Text(
                    'No listening history yet. Play a book to see history.'));
          }
          final grouped = <String, List<dynamic>>{};
          for (final e in entries) {
            final dt = DateTime.fromMillisecondsSinceEpoch(e.startedAtMs);
            final key =
                '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
            grouped.putIfAbsent(key, () => []).add(e);
          }
          return ListView(
            children: grouped.entries.map((g) {
              final day = g.key;
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(day,
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).colorScheme.primary))),
                    ...g.value.map((e) {
                      final start =
                          DateTime.fromMillisecondsSinceEpoch(e.startedAtMs);
                      final listened = Duration(milliseconds: e.listenedMs);
                      final bookTitleAsync = ref.watch(bookProvider(e.bookId));
                      return bookTitleAsync.when(
                        data: (book) => ListTile(
                          leading: const Icon(Icons.headphones),
                          title: Text(book?.title ?? e.bookId,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                              '${formatDateTime(start)} • listened ${formatDuration(listened)} • ${formatDuration(Duration(milliseconds: e.startMs))} → ${formatDuration(Duration(milliseconds: e.endMs))} @ ${e.speed.toStringAsFixed(1)}x'),
                          trailing: const Icon(Icons.chevron_right, size: 16),
                          onTap: () => context.push('/player/${e.bookId}'),
                        ),
                        loading: () => ListTile(
                            title: Text(e.bookId),
                            subtitle: Text(formatDateTime(start))),
                        error: (_, __) => ListTile(title: Text(e.bookId)),
                      );
                    }),
                    const Divider(),
                  ]);
            }).toList(),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}
