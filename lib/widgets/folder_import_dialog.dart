import 'package:flutter/material.dart';
import '../services/library_service.dart';
import '../utils/folder_import.dart';

class FolderImportDialog extends StatefulWidget {
  final List<FolderBook> books;
  final LibraryService library;
  const FolderImportDialog({
    super.key,
    required this.books,
    required this.library,
  });

  @override
  State<FolderImportDialog> createState() => _FolderImportDialogState();
}

class _FolderImportDialogState extends State<FolderImportDialog> {
  late final _selected = widget.books.toSet();
  bool _running = false;
  bool _cancel = false;
  bool _finished = false;
  int _imported = 0;
  String? _current;
  String? _error;

  Future<void> _import() async {
    setState(() => _running = true);
    for (final book in widget.books.where(_selected.contains)) {
      if (_cancel) break;
      setState(() => _current = book.title);
      try {
        await widget.library.importFiles(book.files, title: book.title);
        if (!mounted) return;
        setState(() => _imported++);
      } catch (error) {
        if (!mounted) return;
        setState(() => _error = '${book.title}: $error');
        break;
      }
    }
    if (mounted) {
      setState(() {
        _running = false;
        _finished = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_running,
    child: AlertDialog(
      title: Text(
        _finished
            ? 'Imported $_imported ${_imported == 1 ? 'book' : 'books'}'
            : 'Import library folder',
      ),
      content: SizedBox(
        width: 520,
        child: _running
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$_imported of ${_selected.length} books imported'),
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(_current ?? ''),
                  if (_cancel) const Text('Stopping after the current book…'),
                ],
              )
            : _finished
            ? Text(
                _error != null
                    ? 'Import stopped: $_error\n\nSuccessfully imported books are in your library.'
                    : _cancel
                    ? 'Import stopped. Completed books are in your library.'
                    : 'Your books are ready to play.',
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'One book per audio folder. Numbered CD, Disc and Part folders stay together. Select the books to copy into your library.',
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: widget.books.length,
                      itemBuilder: (context, index) {
                        final book = widget.books[index];
                        return CheckboxListTile(
                          title: Text(book.title),
                          subtitle: Text(
                            '${book.files.length} tracks · ${book.folder}',
                          ),
                          value: _selected.contains(book),
                          onChanged: (value) => setState(() {
                            if (value == true) {
                              _selected.add(book);
                            } else {
                              _selected.remove(book);
                            }
                          }),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        if (_running)
          TextButton(
            onPressed: _cancel ? null : () => setState(() => _cancel = true),
            child: const Text('Stop after this book'),
          )
        else ...[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_finished ? 'Done' : 'Cancel'),
          ),
          if (!_finished)
            FilledButton(
              onPressed: _selected.isEmpty ? null : _import,
              child: Text(
                'Import ${_selected.length} ${_selected.length == 1 ? 'book' : 'books'}',
              ),
            ),
        ],
      ],
    ),
  );
}
