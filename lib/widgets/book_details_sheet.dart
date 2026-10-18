import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../services/db/app_database.dart';

Future<void> showBookDetails(BuildContext context, Book book) => showDialog(
  context: context,
  builder: (_) => _BookDetails(book: book),
);

class _BookDetails extends ConsumerStatefulWidget {
  final Book book;
  const _BookDetails({required this.book});
  @override
  ConsumerState<_BookDetails> createState() => _BookDetailsState();
}

class _BookDetailsState extends ConsumerState<_BookDetails> {
  late final _title = TextEditingController(text: widget.book.title);
  late final _author = TextEditingController(text: widget.book.author);
  late final _series = TextEditingController(text: widget.book.series);
  late final _order = TextEditingController(
    text: widget.book.seriesOrder?.toString() ?? '',
  );
  late final _collection = TextEditingController(text: widget.book.collection);
  Uint8List? _cover;
  String? _error;
  bool _busy = false;
  @override
  void dispose() {
    for (final c in [_title, _author, _series, _order, _collection]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final order = _order.text.trim().isEmpty
        ? null
        : double.tryParse(_order.text.trim());
    if (_title.text.trim().isEmpty ||
        (_order.text.trim().isNotEmpty &&
            (order == null || !order.isFinite || order < 0))) {
      setState(() => _error = 'Enter a title and a valid series number.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_cover != null) {
        await ref
            .read(libraryServiceProvider)
            .setCover(widget.book.id, _cover!);
      }
      await ref.read(playbackProvider).updateBookDetails(widget.book.id, {
        'title': _title.text,
        'author': _author.text,
        'series': _series.text,
        'seriesOrder': order,
        'collection': _collection.text,
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _pickCover() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png'],
      );
      if (files.isEmpty || files.first.path == null) return;
      final file = File(files.first.path!);
      if (await file.length() > 10 * 1024 * 1024) {
        throw const FormatException('Choose an image under 10 MB');
      }
      final bytes = await file.readAsBytes();
      if (mounted) setState(() => _cover = bytes);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Book details'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_cover != null)
              Image.memory(
                _cover!,
                height: 100,
                errorBuilder: (_, _, _) => const Text('Invalid image'),
              ),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title'),
              maxLength: 1000,
            ),
            TextField(
              controller: _author,
              decoration: const InputDecoration(labelText: 'Author'),
              maxLength: 1000,
            ),
            TextField(
              controller: _series,
              decoration: const InputDecoration(labelText: 'Series'),
            ),
            TextField(
              controller: _order,
              decoration: const InputDecoration(labelText: 'Number in series'),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            TextField(
              controller: _collection,
              decoration: const InputDecoration(
                labelText: 'Collection',
                hintText: 'For example: Favorites',
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: _busy ? null : _pickCover,
              icon: const Icon(Icons.image_outlined),
              label: const Text('Change cover'),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _busy ? null : _save,
        child: Text(_busy ? 'Saving…' : 'Save'),
      ),
    ],
  );
}
