import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../widgets/bookmark_tile.dart';

class BookmarksScreen extends ConsumerWidget {
  final String bookId;
  const BookmarksScreen({super.key, required this.bookId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bmsAsync = ref.watch(bookmarksProvider(bookId));
    final svc = ref.watch(playbackProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Bookmarks')),
      body: bmsAsync.when(
        data: (bms) {
          if (bms.isEmpty) {
            return const Center(
                child:
                    Text('No bookmarks yet. Tap bookmark button in player.'));
          }
          return ListView.separated(
            itemCount: bms.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final bm = bms[i];
              return BookmarkTile(
                bookmark: bm,
                onTap: () async {
                  try {
                    await svc.seekBookmark(bm);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Could not open bookmark: $e')));
                    }
                    return;
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Seeked to ${bm.title}')));
                  }
                },
                onDelete: () async {
                  final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                              title: const Text('Delete bookmark?'),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel')),
                                FilledButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: const Text('Delete'))
                              ]));
                  if (ok == true) {
                    await ref.read(bookmarkServiceProvider).delete(bm.id);
                  }
                },
                onEdit: () async {
                  final tCtrl = TextEditingController(text: bm.title);
                  final nCtrl = TextEditingController(text: bm.note ?? '');
                  final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                            title: const Text('Edit bookmark'),
                            content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  TextField(
                                      controller: tCtrl,
                                      decoration: const InputDecoration(
                                          labelText: 'Title')),
                                  TextField(
                                      controller: nCtrl,
                                      decoration: const InputDecoration(
                                          labelText: 'Note'))
                                ]),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel')),
                              FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Save'))
                            ],
                          ));
                  if (ok == true) {
                    await ref.read(bookmarkServiceProvider).update(bm.id,
                        tCtrl.text, nCtrl.text.isEmpty ? null : nCtrl.text);
                  }
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
      floatingActionButton: FloatingActionButton.extended(
          icon: const Icon(Icons.bookmark_add),
          label: const Text('Add'),
          onPressed: () async {
            final titleCtrl = TextEditingController(text: 'Manual');
            final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                        title: const Text('New bookmark'),
                        content: TextField(
                            controller: titleCtrl,
                            decoration:
                                const InputDecoration(labelText: 'Title')),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel')),
                          FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Save'))
                        ]));
            if (ok == true) {
              try {
                await svc.addManualBookmark(title: titleCtrl.text);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Bookmark added')));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('No active book: $e')));
                }
              }
            }
          }),
    );
  }
}
