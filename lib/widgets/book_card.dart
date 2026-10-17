import 'package:flutter/material.dart';
import '../services/db/app_database.dart';
import '../utils/format.dart';
import 'dart:io';

class BookCard extends StatelessWidget {
  final Book book;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  const BookCard({super.key, required this.book, this.onTap, this.onDelete});

  @override
  Widget build(BuildContext context) {
    final progress = book.totalProgress;
    final hasCover = book.coverPath.isNotEmpty && File(book.coverPath).existsSync();
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
                        ? Image.file(File(book.coverPath), fit: BoxFit.cover, errorBuilder: (_,__,___)=> _fallbackIcon(context))
                        : _fallbackIcon(context),
                  ),
                  if (progress > 0)
                    Positioned(
                      bottom: 0, left: 0, right: 0,
                      child: LinearProgressIndicator(value: progress, minHeight: 4, backgroundColor: Colors.black26),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
              child: Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 2),
              child: Text(book.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.7))),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Row(
                children: [
                  Text(formatDuration(Duration(milliseconds: book.totalDurationMs)), style: const TextStyle(fontSize: 10)),
                  const Spacer(),
                  if (book.isFinished) const Icon(Icons.check_circle, size: 14, color: Colors.green),
                  if (onDelete != null) InkWell(onTap: onDelete, child: const Icon(Icons.more_horiz, size: 16)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallbackIcon(BuildContext ctx) => Center(child: Icon(Icons.menu_book, size: 48, color: Theme.of(ctx).colorScheme.onPrimaryContainer.withValues(alpha: 0.8)));
}
