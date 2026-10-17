import 'package:flutter/material.dart';
import '../services/db/app_database.dart';
import '../utils/format.dart';

class BookmarkTile extends StatelessWidget {
  final Bookmark bookmark;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  const BookmarkTile({super.key, required this.bookmark, required this.onTap, required this.onDelete, required this.onEdit});
  @override
  Widget build(BuildContext context) {
    final isAuto = bookmark.kind == 'auto';
    return ListTile(
      leading: Icon(isAuto ? Icons.bookmark_border : Icons.bookmark, color: isAuto ? Colors.grey : Theme.of(context).colorScheme.primary),
      title: Text(bookmark.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(formatDuration(Duration(milliseconds: bookmark.positionMs)), style: const TextStyle(fontSize: 11)),
        if (bookmark.note != null) Text(bookmark.note!, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontStyle: FontStyle.italic)),
        Text(formatDateTime(DateTime.fromMillisecondsSinceEpoch(bookmark.createdAtMs)), style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ]),
      trailing: PopupMenuButton<String>(
        onSelected: (v) { if (v=='edit') onEdit(); if (v=='delete') onDelete(); },
        itemBuilder: (_)=> [const PopupMenuItem(value: 'edit', child: Text('Edit')), const PopupMenuItem(value: 'delete', child: Text('Delete'))],
      ),
      onTap: onTap,
    );
  }
}
