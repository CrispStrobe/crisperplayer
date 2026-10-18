import 'package:flutter/material.dart';
import '../services/db/app_database.dart';
import '../utils/format.dart';

class ChapterTile extends StatelessWidget {
  final Chapter chapter;
  final bool isCurrent;
  final VoidCallback onTap;
  const ChapterTile(
      {super.key,
      required this.chapter,
      this.isCurrent = false,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      selected: isCurrent,
      selectedTileColor:
          Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
      title: Text(chapter.title,
          style: TextStyle(
              fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
      subtitle: Text(
          '${formatDuration(Duration(milliseconds: chapter.startMs))} — ${formatDuration(Duration(milliseconds: chapter.endMs))}'),
      trailing: isCurrent
          ? Icon(Icons.equalizer, color: Theme.of(context).colorScheme.primary)
          : null,
      onTap: onTap,
    );
  }
}
