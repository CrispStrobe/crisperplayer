import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../utils/folder_import.dart';
import '../widgets/folder_import_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/providers.dart';
import '../services/db/app_database.dart';
import '../utils/format.dart';
import '../widgets/mini_player.dart';
import '../widgets/book_details_sheet.dart';
import '../widgets/book_preferences_sheet.dart';
import '../widgets/queue_sheet.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});
  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String _query = '';
  String _filter = 'all';
  String _sortBy = 'recent';
  String _collection = '';
  String _series = '';

  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  static const _statuses = {
    'all': 'All',
    'unfinished': 'Unfinished',
    'unread': 'Unread',
    'recent': 'Recent',
    'finished': 'Finished',
  };
  static const _sorts = {
    'recent': 'Added',
    'lastPlayed': 'Played',
    'title': 'Title',
    'author': 'Author',
    'series': 'Series',
    'duration': 'Duration',
  };

  @override
  Widget build(BuildContext context) {
    final booksAsync = ref.watch(libraryBooksProvider);
    final svc = ref.watch(playbackProvider);
    final settings = ref.watch(settingsProvider);
    final scaler = MediaQuery.textScalerOf(context);
    final list =
        settings.libraryView == 'list' ||
        (settings.libraryView == 'auto' && scaler.scale(14) >= 21);
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: (scaler.scale(20) * 1.4 + 16)
            .clamp(56.0, 112.0)
            .toDouble(),
        title: const Text(
          'CrisperPlayer',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.queue_music),
            tooltip: 'Up next',
            onPressed: () => showQueue(context),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'History',
            onPressed: () => context.push('/history'),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(libraryBooksProvider),
        child: CustomScrollView(
          key: const PageStorageKey('library-scroll'),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _search,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        labelText: 'Search books',
                        hintText: 'Title, author, series or collection',
                        border: const OutlineInputBorder(),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                key: const ValueKey('clear-library-search'),
                                tooltip: 'Clear search',
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _search.clear();
                                  setState(() => _query = '');
                                },
                              ),
                      ),
                      onChanged: (value) => setState(() => _query = value),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _menu(
                          'Reading status',
                          Icons.filter_list,
                          _filter,
                          _statuses,
                          (value) => setState(() {
                            _filter = value;
                            if (value == 'recent') _sortBy = 'lastPlayed';
                          }),
                        ),
                        _menu(
                          'Sort books',
                          Icons.sort,
                          _sortBy,
                          _sorts,
                          (value) => setState(() => _sortBy = value),
                          prefix: 'Sort: ',
                        ),
                        PopupMenuButton<String>(
                          key: const ValueKey('library-layout'),
                          tooltip: 'Library layout',
                          initialValue: settings.libraryView,
                          icon: Icon(
                            list ? Icons.view_list_outlined : Icons.grid_view,
                          ),
                          onSelected: (value) => settings.libraryView = value,
                          itemBuilder: (_) => [
                            for (final entry in const {
                              'auto': 'Automatic',
                              'grid': 'Cover grid',
                              'list': 'List',
                            }.entries)
                              CheckedPopupMenuItem(
                                height:
                                    16 +
                                    MediaQuery.textScalerOf(context).scale(24) *
                                        2,
                                value: entry.key,
                                checked: settings.libraryView == entry.key,
                                child: Text(entry.value),
                              ),
                          ],
                        ),
                      ],
                    ),
                    if ((booksAsync.value ?? []).any(
                      (b) => b.collection.isNotEmpty || b.series.isNotEmpty,
                    ))
                      LayoutBuilder(
                        builder: (_, constraints) {
                          final width = constraints.maxWidth < 560
                              ? constraints.maxWidth
                              : (constraints.maxWidth - 12) / 2;
                          return Wrap(
                            spacing: 12,
                            children: [
                              SizedBox(
                                width: width,
                                child: _groupFilter(
                                  booksAsync.value ?? [],
                                  false,
                                ),
                              ),
                              SizedBox(
                                width: width,
                                child: _groupFilter(
                                  booksAsync.value ?? [],
                                  true,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
            ...booksAsync.when(
              data: (books) {
                final collection = books.any((b) => b.collection == _collection)
                    ? _collection
                    : '';
                final series = books.any((b) => b.series == _series)
                    ? _series
                    : '';
                final query = _query.trim().toLowerCase();
                final filtered = _sortBooks(
                  books
                      .where(
                        (book) =>
                            '${book.title} ${book.author} ${book.series} ${book.collection}'
                                .toLowerCase()
                                .contains(query) &&
                            (collection.isEmpty ||
                                book.collection == collection) &&
                            (series.isEmpty || book.series == series) &&
                            (_filter != 'finished' || book.isFinished) &&
                            (_filter != 'unfinished' || !book.isFinished) &&
                            (_filter != 'unread' ||
                                (!book.isFinished &&
                                    book.totalProgress == 0)) &&
                            (_filter != 'recent' ||
                                book.lastPlayedAtMs != null),
                      )
                      .toList(),
                );
                if (filtered.isEmpty) {
                  return <Widget>[
                    SliverToBoxAdapter(
                      child: books.isEmpty
                          ? _emptyState(context)
                          : const Padding(
                              padding: EdgeInsets.all(24),
                              child: Text('No books match these filters.'),
                            ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 96)),
                  ];
                }
                return <Widget>[
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 96),
                    sliver: list
                        ? SliverList.builder(
                            itemCount: filtered.length,
                            itemBuilder: (_, index) => _BookListItem(
                              book: filtered[index],
                              onTap: () => _openBook(filtered[index]),
                              onMenu: () => _bookMenu(filtered[index]),
                            ),
                          )
                        : SliverLayoutBuilder(
                            builder: (_, constraints) {
                              final maxExtent =
                                  240 *
                                  (scaler.scale(14) / 14)
                                      .clamp(1.0, 4.0)
                                      .toDouble();
                              final columns =
                                  (constraints.crossAxisExtent /
                                          (maxExtent + 8))
                                      .ceil()
                                      .clamp(1, 1000);
                              final cardWidth =
                                  (constraints.crossAxisExtent -
                                      (columns - 1) * 8) /
                                  columns;
                              return SliverGrid.builder(
                                gridDelegate:
                                    SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: maxExtent,
                                      crossAxisSpacing: 8,
                                      mainAxisSpacing: 8,
                                      mainAxisExtent:
                                          cardWidth +
                                          80 +
                                          scaler.scale(13) * 3 +
                                          scaler.scale(11) * 3,
                                    ),
                                itemCount: filtered.length,
                                itemBuilder: (_, index) => _BookCardWithMeta(
                                  book: filtered[index],
                                  onTap: () => _openBook(filtered[index]),
                                  onMenu: () => _bookMenu(filtered[index]),
                                ),
                              );
                            },
                          ),
                  ),
                ];
              },
              loading: () => <Widget>[
                const SliverToBoxAdapter(
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
              error: (error, _) => <Widget>[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('Error: $error'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      bottomNavigationBar: StreamBuilder(
        stream: svc.stateStream,
        initialData: svc.state,
        builder: (_, _) => svc.currentBookId == null
            ? const SizedBox.shrink()
            : const SafeArea(top: false, child: MiniPlayer()),
      ),
      floatingActionButton:
          MediaQuery.sizeOf(context).width < 400 || scaler.scale(14) >= 21
          ? FloatingActionButton(
              tooltip: 'Import audiobooks',
              onPressed: _chooseImport,
              child: const Icon(Icons.add),
            )
          : FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('Import'),
              onPressed: _chooseImport,
            ),
    );
  }

  Widget _menu(
    String label,
    IconData icon,
    String current,
    Map<String, String> values,
    ValueChanged<String> onChanged, {
    String prefix = '',
  }) => PopupMenuButton<String>(
    key: ValueKey(label),
    tooltip: label,
    initialValue: current,
    onSelected: onChanged,
    itemBuilder: (_) => [
      for (final entry in values.entries)
        CheckedPopupMenuItem(
          height: 16 + MediaQuery.textScalerOf(context).scale(24) * 2,
          value: entry.key,
          checked: current == entry.key,
          child: Text(entry.value),
        ),
    ],
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon),
            const SizedBox(width: 8),
            Flexible(child: Text('$prefix${values[current]}')),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    ),
  );

  Future<void> _openBook(Book book) async {
    final svc = ref.read(playbackProvider);
    ref.read(selectedBookIdProvider.notifier).state = book.id;
    try {
      if (svc.currentBookId != book.id) await svc.loadBook(book.id);
      if (mounted) context.push('/player/${book.id}');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not open book: $error')));
      }
    }
  }

  List<Book> _sortBooks(List<Book> books) {
    final list = List<Book>.from(books);
    switch (_sortBy) {
      case 'title':
        list.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
        break;
      case 'series':
        list.sort((a, b) {
          final series = a.series.toLowerCase().compareTo(
            b.series.toLowerCase(),
          );
          if (series != 0) return series;
          final number = (a.seriesOrder ?? double.infinity).compareTo(
            b.seriesOrder ?? double.infinity,
          );
          return number != 0
              ? number
              : a.title.toLowerCase().compareTo(b.title.toLowerCase());
        });
        break;
      case 'author':
        list.sort(
          (a, b) => a.author.toLowerCase().compareTo(b.author.toLowerCase()),
        );
        break;
      case 'duration':
        list.sort((a, b) => b.totalDurationMs.compareTo(a.totalDurationMs));
        break;
      case 'lastPlayed':
        list.sort(
          (a, b) => (b.lastPlayedAtMs ?? 0).compareTo(a.lastPlayedAtMs ?? 0),
        );
        break;
      case 'recent':
        list.sort((a, b) => b.addedAtMs.compareTo(a.addedAtMs));
        break;
    }
    return list;
  }

  Widget _groupFilter(List<Book> books, bool series) {
    final groups =
        books
            .map((b) => series ? b.series : b.collection)
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final current = series ? _series : _collection;
    return DropdownButton<String>(
      isExpanded: true,
      itemHeight: null,
      value: groups.contains(current) ? current : '',
      items: [
        DropdownMenuItem(
          value: '',
          child: Text(
            series ? 'All series' : 'All collections',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        for (final group in groups)
          DropdownMenuItem(
            value: group,
            child: Text(group, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) => setState(() {
        if (series) {
          _series = v!;
        } else {
          _collection = v!;
        }
      }),
    );
  }

  Future<void> _bookMenu(Book book) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  book.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              for (final entry in {
                'edit': 'Edit book details',
                'preferences': 'Playback for this book',
                'next': 'Play next',
                'enqueue': 'Add to end of queue',
                'finished': book.isFinished
                    ? 'Mark unfinished'
                    : 'Mark finished',
                'unread': 'Reset to unread',
                'metadata': 'Reload embedded metadata',
                'delete': 'Delete book',
              }.entries)
                ListTile(
                  title: Text(entry.value),
                  onTap: () => Navigator.pop(context, entry.key),
                ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    final svc = ref.read(playbackProvider);
    try {
      switch (action) {
        case 'edit':
          await showBookDetails(context, book);
        case 'preferences':
          await showBookPreferences(context, book);
        case 'next':
          await svc.enqueue(book.id, position: 0);
        case 'enqueue':
          await svc.enqueue(book.id);
        case 'finished':
          await svc.markBook(
            book.id,
            book.isFinished ? 'unfinished' : 'finished',
          );
        case 'unread':
          await svc.markBook(book.id, 'unread');
        case 'metadata':
          final updated = await ref
              .read(libraryServiceProvider)
              .refreshMetadata(book.id);
          await svc.updateBookDetails(book.id, {});
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  updated ? 'Metadata updated' : 'No embedded metadata found',
                ),
              ),
            );
          }
        case 'delete':
          await _confirmDelete(book.id, book.title);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Widget _emptyState(BuildContext ctx) {
    final cs = Theme.of(ctx).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: cs.surface,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.library_music_rounded,
                      size: 48,
                      color: cs.primary.withValues(alpha: 0.7),
                    ),
                  ),
                  Positioned(
                    right: 24,
                    bottom: 28,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: cs.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.add,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Your library is empty',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Import m4b, m4a, mp3, flac, ogg, wav and more.\nWe track progress and bookmarks automatically.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(
                  ctx,
                ).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: const Icon(Icons.file_open),
              label: const Text('Import audiobooks'),
              onPressed: _chooseImport,
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.folder_open, size: 16),
              label: const Text(
                'Supported: m4b • m4a • mp3 • flac • ogg • wav • aac • opus • wma',
              ),
              onPressed: null,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _chooseImport() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.audio_file_outlined),
              title: const Text('Import audio files'),
              onTap: () => Navigator.pop(context, 'files'),
            ),
            if (Platform.isMacOS ||
                Platform.isWindows ||
                Platform.isLinux ||
                Platform.isAndroid)
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: const Text('Import folder as one book'),
                onTap: () => Navigator.pop(context, 'folder'),
              ),
            if (Platform.isMacOS ||
                Platform.isWindows ||
                Platform.isLinux ||
                Platform.isAndroid)
              ListTile(
                leading: const Icon(Icons.library_books_outlined),
                title: const Text('Import library folder / mounted share'),
                subtitle: const Text('Review separate books in nested folders'),
                onTap: () => Navigator.pop(context, 'library'),
              ),
            ListTile(
              leading: const Icon(Icons.dns_outlined),
              title: const Text('Plex / WebDAV / SFTP server'),
              onTap: () => Navigator.pop(context, 'server'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'files') await _import();
    if (choice == 'server' && mounted) context.push('/settings/sync');
    if (choice == 'folder' || choice == 'library') {
      try {
        final path = await FilePicker.getDirectoryPath();
        if (path == null) return;
        final books = await scanBookFolders(path);
        if (books.isEmpty) {
          throw const FormatException(
            'No supported audio files in this folder',
          );
        }
        if (!mounted) return;
        final library = ref.read(libraryServiceProvider);
        if (choice == 'library') {
          await showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (_) => FolderImportDialog(books: books, library: library),
          );
          return;
        }
        await library.importFiles([for (final book in books) ...book.files]);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Folder imported as one book')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
        }
      }
    }
  }

  Future<void> _import() async {
    try {
      await _importFiles();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    }
  }

  Future<void> _importFiles() async {
    final lib = ref.read(libraryServiceProvider);
    final paths = await lib.pickAudioFiles();
    if (paths.isEmpty) return;
    if (!mounted) return;
    String? groupTitle;
    if (paths.length > 1) {
      groupTitle = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Import'),
          content: Text(
            '${paths.length} files selected. Import as single audiobook (e.g. multi-file book) or as separate books?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'separate'),
              child: const Text('Separate books'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'single'),
              child: const Text('Single book'),
            ),
          ],
        ),
      );
      if (groupTitle == null) return;
    }
    if (groupTitle == 'single') {
      await lib.importFiles(paths);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported ${paths.length} files as one book')),
        );
      }
    } else if (groupTitle == 'separate') {
      for (final pth in paths) {
        await lib.importFiles([pth]);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported ${paths.length} books')),
        );
      }
    } else {
      await lib.importFiles(paths);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Book imported')));
      }
    }
  }

  Future<void> _confirmDelete(String id, String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "$title"?'),
        content: const Text(
          'This removes the book and its managed audio copies. Your original source files stay on disk.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(libraryServiceProvider).deleteBook(id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Deleted')));
      }
    }
  }
}

class _BookListItem extends StatelessWidget {
  final Book book;
  final VoidCallback onTap;
  final VoidCallback onMenu;
  const _BookListItem({
    required this.book,
    required this.onTap,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final status = book.isFinished
        ? 'Finished'
        : book.totalProgress > 0
        ? '${(book.totalProgress * 100).round()}% complete'
        : 'Not started';
    final duration = book.totalDurationMs > 0
        ? formatDuration(Duration(milliseconds: book.totalDurationMs))
        : 'Duration unavailable';
    final spokenDuration = book.totalDurationMs > 0
        ? formatSpokenDuration(Duration(milliseconds: book.totalDurationMs))
        : 'Duration unavailable';
    final series = book.series.isEmpty
        ? ''
        : '${book.series}${book.seriesOrder == null ? '' : ' • ${book.seriesOrder!.toString().replaceFirst(RegExp(r'\.0$'), '')}'}';
    return Card(
      child: ListTile(
        key: ValueKey('book-list-${book.id}'),
        contentPadding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        leading: ExcludeSemantics(
          child: SizedBox(
            width: 48,
            height: 48,
            child: book.coverPath.isEmpty
                ? const Icon(Icons.menu_book)
                : ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.file(
                      File(book.coverPath),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(Icons.menu_book),
                    ),
                  ),
          ),
        ),
        title: Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Semantics(
          label:
              '${book.author}${series.isEmpty ? '' : ', $series'}, $spokenDuration, $status',
          excludeSemantics: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(book.author, maxLines: 2, overflow: TextOverflow.ellipsis),
              if (series.isNotEmpty)
                Text(series, maxLines: 2, overflow: TextOverflow.ellipsis),
              Wrap(
                spacing: 8,
                children: [
                  Text(duration, maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text(status, maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ),
            ],
          ),
        ),
        trailing: IconButton(
          key: ValueKey('book-actions-${book.id}'),
          tooltip: 'Actions for ${book.title}',
          icon: const Icon(Icons.more_horiz),
          onPressed: onMenu,
        ),
        onTap: onTap,
      ),
    );
  }
}

class _BookCardWithMeta extends StatelessWidget {
  final Book book;
  final VoidCallback? onTap;
  final VoidCallback? onMenu;
  const _BookCardWithMeta({required this.book, this.onTap, this.onMenu});
  @override
  Widget build(BuildContext context) {
    final progress = book.totalProgress;
    final hasCover = book.coverPath.isNotEmpty;
    final lastPlayed = book.lastPlayedAtMs != null
        ? DateTime.fromMillisecondsSinceEpoch(book.lastPlayedAtMs!)
        : null;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: hasCover
                        ? Image.file(
                            File(book.coverPath),
                            excludeFromSemantics: true,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _coverFallback(context),
                          )
                        : _coverFallback(context),
                  ),
                  if (progress > 0)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        backgroundColor: Colors.black26,
                      ),
                    ),
                  if (book.isFinished)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check, size: 10, color: Colors.white),
                            SizedBox(width: 2),
                            Text(
                              'Done',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
              child: Text(
                book.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 2),
              child: Text(
                book.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(
                    context,
                  ).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                ),
              ),
            ),
            if (book.series.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 2),
                child: Text(
                  '${book.series}${book.seriesOrder == null ? '' : ' • ${book.seriesOrder!.toString().replaceFirst(RegExp(r'\.0$'), '')}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 2),
              child: Row(
                children: [
                  Icon(
                    Icons.schedule,
                    size: 10,
                    color: Theme.of(
                      context,
                    ).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    formatDuration(
                      Duration(milliseconds: book.totalDurationMs),
                    ),
                    style: const TextStyle(fontSize: 10),
                  ),
                  const Spacer(),
                  if (book.isFinished)
                    const Icon(
                      Icons.check_circle,
                      size: 14,
                      color: Colors.green,
                    ),
                ],
              ),
            ),
            if (lastPlayed != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.play_circle_outline,
                      size: 10,
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        formatDateTime(lastPlayed),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.9),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (onMenu != null)
                      IconButton(
                        key: ValueKey('book-actions-${book.id}'),
                        tooltip: 'Actions for ${book.title}',
                        onPressed: onMenu,
                        icon: const Icon(Icons.more_horiz, size: 18),
                      ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Not started',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(
                            context,
                          ).textTheme.bodySmall?.color?.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    if (onMenu != null)
                      IconButton(
                        key: ValueKey('book-actions-${book.id}'),
                        tooltip: 'Actions for ${book.title}',
                        onPressed: onMenu,
                        icon: const Icon(Icons.more_horiz, size: 18),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _coverFallback(BuildContext ctx) {
    final cs = Theme.of(ctx).colorScheme;
    final initial = book.title.trim().isNotEmpty
        ? book.title.trim().characters.first.toUpperCase()
        : '?';
    return ExcludeSemantics(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [cs.primaryContainer, cs.primary.withValues(alpha: 0.6)],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    initial,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: cs.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Icon(
                Icons.menu_book_rounded,
                size: 18,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
