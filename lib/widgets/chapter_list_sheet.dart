import 'package:flutter/material.dart';
import '../services/db/app_database.dart';
import '../utils/format.dart';
import '../services/audio/playback_service.dart';

Future<void> showChapterListSheet(
  BuildContext context, {
  required List<Chapter> chapters,
  required Duration position,
  required PlaybackService svc,
}) {
  return showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (ctx2, scrollCtrl) => _ChapterSheet(
        chapters: chapters,
        position: position,
        svc: svc,
        scrollController: scrollCtrl,
      ),
    ),
  );
}

class _ChapterSheet extends StatelessWidget {
  final List<Chapter> chapters;
  final Duration position;
  final PlaybackService svc;
  final ScrollController scrollController;

  const _ChapterSheet({
    required this.chapters,
    required this.position,
    required this.svc,
    required this.scrollController,
  });

  Chapter? _current(Duration pos) {
    Duration bookPos;
    try {
      bookPos = svc.bookPosition;
    } catch (_) {
      bookPos = pos;
    }
    for (final c in chapters) {
      if (bookPos.inMilliseconds >= c.startMs &&
          bookPos.inMilliseconds < c.endMs) {
        return c;
      }
    }
    return chapters.isEmpty ? null : chapters.first;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cur = _current(position);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Row(children: [
            Icon(Icons.list, color: cs.primary),
            const SizedBox(width: 10),
            Text('Chapters', style: Theme.of(context).textTheme.titleLarge),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20)),
              child: Text('${chapters.length} chapters',
                  style: const TextStyle(fontSize: 12)),
            ),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            controller: scrollController,
            itemCount: chapters.length,
            itemBuilder: (ctx, i) {
              final ch = chapters[i];
              final isCur = cur?.id == ch.id;
              final start = Duration(milliseconds: ch.startMs);
              final end = Duration(milliseconds: ch.endMs);
              return ListTile(
                dense: false,
                selected: isCur,
                selectedTileColor: cs.primaryContainer.withValues(alpha: 0.35),
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor:
                      isCur ? cs.primary : cs.surfaceContainerHighest,
                  child: isCur
                      ? Icon(Icons.equalizer, size: 16, color: cs.onPrimary)
                      : Text('${i + 1}',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: cs.onSurfaceVariant)),
                ),
                title: Text(ch.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: isCur ? FontWeight.w700 : FontWeight.w500)),
                subtitle: Text(
                    '${formatDuration(start)} — ${formatDuration(end)}  •  ${formatDuration(end - start)}'),
                trailing: isCur
                    ? Icon(Icons.play_arrow_rounded, color: cs.primary)
                    : const Icon(Icons.chevron_right, size: 18),
                onTap: () async {
                  Navigator.pop(context);
                  await svc.seekChapter(ch);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
