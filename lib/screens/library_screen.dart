import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/providers.dart';
import '../services/db/app_database.dart';
import '../utils/format.dart';
import '../widgets/mini_player.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});
  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String _query = '';
  String _filter = 'all';
  String _sortBy = 'recent';

  @override
  Widget build(BuildContext context) {
    final booksAsync = ref.watch(libraryBooksProvider);
    final svc = ref.watch(playbackProvider);
    final hasMini = svc.currentBookId != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('CrisperPlayer'),
        actions: [
          IconButton(icon: const Icon(Icons.history), tooltip: 'History', onPressed: () => context.push('/history')),
          IconButton(icon: const Icon(Icons.settings), tooltip: 'Settings', onPressed: () => context.push('/settings')),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search books…', isDense: true, border: OutlineInputBorder()), onChanged: (v) => setState(() => _query = v))),
                    const SizedBox(width: 8),
                    DropdownButton<String>(value: _filter, underline: const SizedBox.shrink(), items: const [DropdownMenuItem(value: 'all', child: Text('All')), DropdownMenuItem(value: 'recent', child: Text('Recent')), DropdownMenuItem(value: 'finished', child: Text('Finished'))], onChanged: (v) => setState(() => _filter = v!)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.sort, size: 16),
                    const SizedBox(width: 6),
                    const Text('Sort by:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                    const SizedBox(width: 8),
                    Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: SegmentedButton<String>(showSelectedIcon: false, style: ButtonStyle(visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap, textStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12))), segments: const [ButtonSegment(value: 'recent', label: Text('Added')), ButtonSegment(value: 'lastPlayed', label: Text('Played')), ButtonSegment(value: 'title', label: Text('Title')), ButtonSegment(value: 'author', label: Text('Author')), ButtonSegment(value: 'duration', label: Text('Duration'))], selected: {_sortBy}, onSelectionChanged: (s) => setState(() => _sortBy = s.first)))),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(children: [
        Expanded(child: booksAsync.when(data: (books) { var filtered = books.where((b) => _query.isEmpty || b.title.toLowerCase().contains(_query.toLowerCase()) || b.author.toLowerCase().contains(_query.toLowerCase())).toList(); if (_filter == 'recent') filtered.sort((a, b) => (b.lastPlayedAtMs ?? 0).compareTo(a.lastPlayedAtMs ?? 0)); if (_filter == 'finished') filtered = filtered.where((b) => b.isFinished).toList(); filtered = _sortBooks(filtered); if (filtered.isEmpty) return _emptyState(context); return RefreshIndicator(onRefresh: () async => ref.invalidate(libraryBooksProvider), child: GridView.builder(padding: const EdgeInsets.all(8), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 0.58, crossAxisSpacing: 8, mainAxisSpacing: 8), itemCount: filtered.length, itemBuilder: (_, i) { final b = filtered[i]; return _BookCardWithMeta(book: b, onTap: () async { ref.read(selectedBookIdProvider.notifier).state = b.id; if (svc.currentBookId != b.id) await svc.loadBook(b.id); if (context.mounted) context.push('/player/${b.id}'); }, onDelete: () => _confirmDelete(b.id, b.title)); })); }, loading: () => const Center(child: CircularProgressIndicator()), error: (e, st) => Center(child: Text('Error: \$e')))),
        if (hasMini) const MiniPlayer(),
      ]),
      floatingActionButton: FloatingActionButton.extended(icon: const Icon(Icons.add), label: const Text('Import'), onPressed: _import),
    );
  }
  List<Book> _sortBooks(List<Book> books) { final list = List<Book>.from(books); switch (_sortBy) { case 'title': list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase())); break; case 'author': list.sort((a, b) => a.author.toLowerCase().compareTo(b.author.toLowerCase())); break; case 'duration': list.sort((a, b) => b.totalDurationMs.compareTo(a.totalDurationMs)); break; case 'lastPlayed': list.sort((a, b) => (b.lastPlayedAtMs ?? 0).compareTo(a.lastPlayedAtMs ?? 0)); break; case 'recent': list.sort((a, b) => b.addedAtMs.compareTo(a.addedAtMs)); break; } return list; }
  Widget _emptyState(BuildContext ctx) { final cs = Theme.of(ctx).colorScheme; return Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Container(width: 160, height: 160, decoration: BoxDecoration(color: cs.primaryContainer.withValues(alpha: 0.6), shape: BoxShape.circle), child: Stack(alignment: Alignment.center, children: [Container(width: 120, height: 120, decoration: BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle)), Container(width: 88, height: 88, decoration: BoxDecoration(color: cs.surface, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 4))]), child: Icon(Icons.library_music_rounded, size: 48, color: cs.primary.withValues(alpha: 0.7))), Positioned(right: 24, bottom: 28, child: Container(width: 32, height: 32, decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle), child: const Icon(Icons.add, color: Colors.white, size: 18)))] )), const SizedBox(height: 20), const Text('Your library is empty', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 8), Text('Import m4b, m4a, mp3, flac, ogg, wav and more.\nWe track progress and bookmarks automatically.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: Theme.of(ctx).textTheme.bodySmall?.color?.withValues(alpha: 0.7))), const SizedBox(height: 20), FilledButton.icon(icon: const Icon(Icons.file_open), label: const Text('Import audiobooks'), onPressed: _import), const SizedBox(height: 8), TextButton.icon(icon: const Icon(Icons.folder_open, size: 16), label: const Text('Supported: m4b • m4a • mp3 • flac • ogg • wav • aac • opus • wma'), onPressed: null) ]))); }
  Future<void> _import() async { final lib = ref.read(libraryServiceProvider); final paths = await lib.pickAudioFiles(); if (paths.isEmpty) return; if (!mounted) return; String? groupTitle; if (paths.length > 1) { groupTitle = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: const Text('Import'), content: Text('\${paths.length} files selected. Import as single audiobook (e.g. multi-file book) or as separate books?'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, 'separate'), child: const Text('Separate books')), FilledButton(onPressed: () => Navigator.pop(ctx, 'single'), child: const Text('Single book'))])); if (groupTitle == null) return; } if (groupTitle == 'single') { await lib.importFiles(paths); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Imported \${paths.length} files as one book'))); } else if (groupTitle == 'separate') { for (final pth in paths) { await lib.importFiles([pth]); } if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Imported \${paths.length} books'))); } else { await lib.importFiles(paths); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Book imported'))); } }
  Future<void> _confirmDelete(String id, String title) async { final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(title: Text('Delete \"\$title\"?'), content: const Text('This removes the book from your library (files stay on disk).'), actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete'))])); if (ok == true) { await ref.read(libraryServiceProvider).deleteBook(id); if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted'))); } }
}
class _BookCardWithMeta extends StatelessWidget {
  final Book book;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  const _BookCardWithMeta({required this.book, this.onTap, this.onDelete});
  @override
  Widget build(BuildContext context) {
    final progress = book.totalProgress;
    final hasCover = book.coverPath.isNotEmpty && File(book.coverPath).existsSync();
    final lastPlayed = book.lastPlayedAtMs != null ? DateTime.fromMillisecondsSinceEpoch(book.lastPlayedAtMs!) : null;
    return Card(clipBehavior: Clip.antiAlias, child: InkWell(onTap: onTap, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: Stack(fit: StackFit.expand, children: [Container(color: Theme.of(context).colorScheme.primaryContainer, child: hasCover ? Image.file(File(book.coverPath), fit: BoxFit.cover, errorBuilder: (_, __, ___) => _coverFallback(context)) : _coverFallback(context)), if (progress > 0) Positioned(bottom: 0, left: 0, right: 0, child: LinearProgressIndicator(value: progress, minHeight: 4, backgroundColor: Colors.black26)), if (book.isFinished) Positioned(top: 6, right: 6, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(8)), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.check, size: 10, color: Colors.white), SizedBox(width: 2), Text('Done', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold))])) )])), Padding(padding: const EdgeInsets.fromLTRB(10, 8, 10, 2), child: Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))), Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 2), child: Text(book.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.7)))), Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 2), child: Row(children: [Icon(Icons.schedule, size: 10, color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6)), const SizedBox(width: 3), Text(formatDuration(Duration(milliseconds: book.totalDurationMs)), style: const TextStyle(fontSize: 10)), const Spacer(), if (book.isFinished) const Icon(Icons.check_circle, size: 14, color: Colors.green)])), if (lastPlayed != null) Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 6), child: Row(children: [Icon(Icons.play_circle_outline, size: 10, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8)), const SizedBox(width: 3), Expanded(child: Text(formatDateTime(lastPlayed), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.9), fontWeight: FontWeight.w500))), if (onDelete != null) InkWell(onTap: onDelete, child: const Icon(Icons.more_horiz, size: 16))])) else Padding(padding: const EdgeInsets.fromLTRB(10, 0, 10, 6), child: Row(children: [Text('Not started', style: TextStyle(fontSize: 10, color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.5))), const Spacer(), if (onDelete != null) InkWell(onTap: onDelete, child: const Icon(Icons.more_horiz, size: 16))]))])));
  }
  Widget _coverFallback(BuildContext ctx) { final cs = Theme.of(ctx).colorScheme; final initial = book.title.isNotEmpty ? book.title.trim()[0].toUpperCase() : '?'; return Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [cs.primaryContainer, cs.primary.withValues(alpha: 0.6)])), child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Container(width: 52, height: 52, decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), shape: BoxShape.circle), child: Center(child: Text(initial, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: cs.primary)))), const SizedBox(height: 6), Icon(Icons.menu_book_rounded, size: 18, color: Colors.white.withValues(alpha: 0.8))]))); }
}
