import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/providers.dart';
import '../widgets/book_card.dart';
import '../widgets/mini_player.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});
  @override
  ConsumerState<LibraryScreen> createState()=> _LibraryScreenState();
}
class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String _query = '';
  String _filter = 'all'; // all, recent, finished

  @override
  Widget build(BuildContext context) {
    final booksAsync = ref.watch(libraryBooksProvider);
    final svc = ref.watch(playbackProvider);
    final hasMini = svc.currentBookId != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('CrisperPlayer'),
        actions: [
          IconButton(icon: const Icon(Icons.history), tooltip: 'History', onPressed: ()=> context.push('/history')),
          IconButton(icon: const Icon(Icons.settings), onPressed: ()=> context.push('/settings')),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12,0,12,10),
            child: Row(children: [
              Expanded(child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search books…', isDense: true, border: OutlineInputBorder()), onChanged: (v)=> setState(()=> _query=v))),
              const SizedBox(width: 8),
              DropdownButton<String>(value: _filter, underline: const SizedBox.shrink(), items: const [DropdownMenuItem(value:'all', child: Text('All')), DropdownMenuItem(value:'recent', child: Text('Recent')), DropdownMenuItem(value:'finished', child: Text('Finished'))], onChanged: (v)=> setState(()=> _filter=v!)),
            ]),
          ),
        ),
      ),
      body: Column(children: [
        Expanded(
          child: booksAsync.when(
            data: (books) {
              var filtered = books.where((b)=> _query.isEmpty || b.title.toLowerCase().contains(_query.toLowerCase()) || b.author.toLowerCase().contains(_query.toLowerCase())).toList();
              if (_filter=='recent') filtered.sort((a,b)=> (b.lastPlayedAtMs??0).compareTo(a.lastPlayedAtMs??0));
              if (_filter=='finished') filtered = filtered.where((b)=> b.isFinished).toList();
              if (filtered.isEmpty) return _emptyState(context);
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(libraryBooksProvider),
                child: GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 0.66, crossAxisSpacing: 8, mainAxisSpacing: 8),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final b = filtered[i];
                    return BookCard(
                      book: b,
                      onTap: () async {
                        ref.read(selectedBookIdProvider.notifier).state = b.id;
                        // load but don't auto-play if already playing same book
                        if (svc.currentBookId != b.id) await svc.loadBook(b.id);
                        if (context.mounted) context.push('/player/${b.id}');
                      },
                      onDelete: ()=> _confirmDelete(b.id, b.title),
                    );
                  },
                ),
              );
            },
            loading: ()=> const Center(child: CircularProgressIndicator()),
            error: (e,st)=> Center(child: Text('Error: $e')),
          ),
        ),
        if (hasMini) const MiniPlayer(),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Import'),
        onPressed: _import,
      ),
    );
  }

  Widget _emptyState(BuildContext ctx) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.library_music, size: 72, color: Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.6)),
    const SizedBox(height: 16),
    const Text('No books yet', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
    const SizedBox(height: 8),
    const Text('Import m4b, m4a, mp3, flac, ogg, wav and more. We track progress and bookmarks automatically.', textAlign: TextAlign.center),
    const SizedBox(height: 16),
    FilledButton.icon(icon: const Icon(Icons.file_open), label: const Text('Import audiobooks'), onPressed: _import),
  ])));

  Future<void> _import() async {
    final lib = ref.read(libraryServiceProvider);
    final paths = await lib.pickAudioFiles();
    if (paths.isEmpty) return;
    if (!mounted) return;
    // if multiple files, ask if they belong to one book or separate
    String? groupTitle;
    if (paths.length > 1) {
      groupTitle = await showDialog<String>(context: context, builder: (ctx)=> AlertDialog(
        title: const Text('Import'),
        content: Text('${paths.length} files selected. Import as single audiobook (e.g. multi-file book) or as separate books?'),
        actions: [
          TextButton(onPressed: ()=> Navigator.pop(ctx, 'separate'), child: const Text('Separate books')),
          FilledButton(onPressed: ()=> Navigator.pop(ctx, 'single'), child: const Text('Single book')),
        ],
      ));
      if (groupTitle == null) return;
    }
    if (groupTitle == 'single') {
      await lib.importFiles(paths);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Imported ${paths.length} files as one book')));
    } else if (groupTitle == 'separate') {
      for (final pth in paths) {
        await lib.importFiles([pth]);
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Imported ${paths.length} books')));
    } else {
      await lib.importFiles(paths);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Book imported')));
    }
  }

  Future<void> _confirmDelete(String id, String title) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx)=> AlertDialog(title: Text('Delete "$title"?'), content: const Text('This removes the book from your library (files stay on disk).'), actions: [TextButton(onPressed: ()=> Navigator.pop(ctx,false), child: const Text('Cancel')), FilledButton(onPressed: ()=> Navigator.pop(ctx,true), child: const Text('Delete'))]));
    if (ok == true) {
      await ref.read(libraryServiceProvider).deleteBook(id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted')));
    }
  }
}
