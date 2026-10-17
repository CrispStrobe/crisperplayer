import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/providers.dart';
import '../utils/format.dart';
import '../widgets/chapter_tile.dart';
import '../services/db/app_database.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  final String bookId;
  const PlayerScreen({super.key, required this.bookId});
  @override
  ConsumerState<PlayerScreen> createState()=> _PlayerScreenState();
}
class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  bool _showChapters = false;
  double _pendingSpeed = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final svc = ref.read(playbackProvider);
      if (svc.currentBookId != widget.bookId) {
        try { await svc.loadBook(widget.bookId); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Load failed: $e'))); }
      }
      _pendingSpeed = svc.state.speed;
    });
  }

  @override
  Widget build(BuildContext context) {
    final svc = ref.watch(playbackProvider);
    final bookAsync = ref.watch(bookProvider(widget.bookId));
    final chaptersAsync = ref.watch(chaptersProvider(widget.bookId));
    final bookmarksAsync = ref.watch(bookmarksProvider(widget.bookId));
    return bookAsync.when(
      data: (book) {
        if (book==null) return Scaffold(appBar: AppBar(title: const Text('Not found')), body: const Center(child: Text('Book not found')));
        return StreamBuilder(
          stream: svc.stateStream,
          initialData: svc.state,
          builder: (ctx, snap) {
            final st = snap.data ?? svc.state;
            final hasCover = book.coverPath.isNotEmpty && File(book.coverPath).existsSync();
            return Scaffold(
              appBar: AppBar(
                title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                actions: [
                  IconButton(icon: const Icon(Icons.bookmark_border), tooltip: 'Bookmarks', onPressed: ()=> context.push('/bookmarks/${widget.bookId}')),
                  PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v=='sleep15') svc.setSleepTimer(const Duration(minutes: 15));
                      if (v=='sleep30') svc.setSleepTimer(const Duration(minutes: 30));
                      if (v=='sleep60') svc.setSleepTimer(const Duration(minutes: 60));
                      if (v=='sleepOff') svc.cancelSleepTimer();
                      if (v=='sleepEoc') svc.setSleepTimer(Duration.zero, endOfChapter: true);
                      if (v=='chapters') setState(()=> _showChapters = !_showChapters);
                    },
                    itemBuilder: (_)=> [
                      const PopupMenuItem(value:'sleep15', child: Text('Sleep 15 min')),
                      const PopupMenuItem(value:'sleep30', child: Text('Sleep 30 min')),
                      const PopupMenuItem(value:'sleep60', child: Text('Sleep 60 min')),
                      const PopupMenuItem(value:'sleepEoc', child: Text('End of chapter')),
                      const PopupMenuItem(value:'sleepOff', child: Text('Cancel sleep timer')),
                      const PopupMenuDivider(),
                      PopupMenuItem(value:'chapters', child: Text(_showChapters? 'Hide chapters' : 'Show chapters')),
                    ],
                  ),
                ],
              ),
              body: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          AspectRatio(
                            aspectRatio: 1,
                            child: Container(
                              decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), color: Theme.of(context).colorScheme.primaryContainer),
                              clipBehavior: Clip.antiAlias,
                              child: hasCover ? Image.file(File(book.coverPath), fit: BoxFit.cover) : Icon(Icons.menu_book, size: 96, color: Theme.of(context).colorScheme.onPrimaryContainer),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(book.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          Text(book.author, style: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.7))),
                          const SizedBox(height: 6),
                          if (svc.sleepRemaining != Duration.zero)
                            Chip(label: Text('Sleep: ${formatDuration(svc.sleepRemaining)}'), onDeleted: ()=> svc.cancelSleepTimer(), deleteIcon: const Icon(Icons.close, size: 16)),
                          if (svc.isWaitingForChapterEnd)
                            Chip(label: const Text('Sleep: end of chapter'), onDeleted: ()=> svc.cancelSleepTimer(), deleteIcon: const Icon(Icons.close, size: 16)),
                          if (svc.sleepEndOfChapter && svc.sleepRemaining != Duration.zero)
                            Chip(label: Text('Sleep: ${formatDuration(svc.sleepRemaining)} → end of chapter'), onDeleted: ()=> svc.cancelSleepTimer(), deleteIcon: const Icon(Icons.close, size: 16)),
                          const SizedBox(height: 12),
                          Slider(
                            min: 0, max: (st.duration.inMilliseconds.toDouble() > 0 ? st.duration.inMilliseconds.toDouble() : 1),
                            value: st.position.inMilliseconds.clamp(0, st.duration.inMilliseconds).toDouble(),
                            onChanged: (v)=> svc.seek(Duration(milliseconds: v.round())),
                          ),
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                            Text(formatDuration(st.position), style: const TextStyle(fontSize: 12)),
                            Text(formatDuration(st.duration), style: const TextStyle(fontSize: 12)),
                            Text('${(st.progress*100).toStringAsFixed(0)}%', style: const TextStyle(fontSize: 12)),
                          ]),
                          const SizedBox(height: 8),
                          chaptersAsync.when(
                            data: (chs) {
                              if (chs.isEmpty) return const SizedBox.shrink();
                              final cur = _currentChapter(chs, st.position, svc);
                              return Text(cur?.title ?? '', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600));
                            },
                            loading: ()=> const SizedBox.shrink(),
                            error: (_,__)=> const SizedBox.shrink(),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              IconButton(icon: const Icon(Icons.skip_previous), iconSize: 36, onPressed: ()=> svc.previousTrack()),
                              IconButton(icon: const Icon(Icons.replay_30), iconSize: 36, onPressed: ()=> svc.skipBack()),
                              FilledButton(
                                style: FilledButton.styleFrom(shape: const CircleBorder(), padding: const EdgeInsets.all(18)),
                                onPressed: ()=> st.isPlaying ? svc.pause() : svc.play(),
                                child: Icon(st.isPlaying ? Icons.pause : Icons.play_arrow, size: 36),
                              ),
                              IconButton(icon: const Icon(Icons.forward_30), iconSize: 36, onPressed: ()=> svc.skipForward()),
                              IconButton(icon: const Icon(Icons.skip_next), iconSize: 36, onPressed: ()=> svc.nextTrack()),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(children: [
                            const Icon(Icons.speed, size: 18), const SizedBox(width: 6),
                            Expanded(child: Slider(min: 0.5, max: 3.0, divisions: 25, label: '${_pendingSpeed.toStringAsFixed(2)}x', value: _pendingSpeed, onChanged: (v)=> setState(()=> _pendingSpeed=v), onChangeEnd: (v)=> svc.setSpeed(v))),
                            Text('${_pendingSpeed.toStringAsFixed(1)}x', style: const TextStyle(fontSize: 12)),
                          ]),
                          const SizedBox(height: 8),
                          bookmarksAsync.when(
                            data: (bms) {
                              if (bms.isEmpty) return const SizedBox.shrink();
                              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                                Row(children: [const Text('Bookmarks', style: TextStyle(fontWeight: FontWeight.bold)), const Spacer(), TextButton(onPressed: ()=> context.push('/bookmarks/${widget.bookId}'), child: const Text('View all'))]),
                                ...bms.take(3).map((bm)=> ListTile(dense: true, leading: Icon(bm.kind=='auto'? Icons.bookmark_border: Icons.bookmark, size: 18), title: Text(bm.title, maxLines: 1), subtitle: Text(formatDuration(Duration(milliseconds: bm.positionMs))), onTap: () async {
                                  await svc.seek(Duration(milliseconds: bm.positionMs));
                                })),
                              ]);
                            },
                            loading: ()=> const SizedBox.shrink(),
                            error: (_,__)=> const SizedBox.shrink(),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(icon: const Icon(Icons.bookmark_add), label: const Text('Add bookmark'), onPressed: () async {
                            final titleCtrl = TextEditingController(text: 'Bookmark @ ${formatDuration(st.position)}');
                            final noteCtrl = TextEditingController();
                            final ok = await showDialog<bool>(context: context, builder: (ctx)=> AlertDialog(
                              title: const Text('New bookmark'),
                              content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: titleCtrl, decoration: const InputDecoration(labelText: 'Title')), TextField(controller: noteCtrl, decoration: const InputDecoration(labelText: 'Note (optional)'))]),
                              actions: [TextButton(onPressed: ()=> Navigator.pop(ctx,false), child: const Text('Cancel')), FilledButton(onPressed: ()=> Navigator.pop(ctx,true), child: const Text('Save'))],
                            ));
                            if (ok==true) {
                              await svc.addManualBookmark(title: titleCtrl.text, note: noteCtrl.text.isEmpty? null : noteCtrl.text);
                              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bookmark saved')));
                            }
                          }),
                          if (_showChapters) ...[
                            const Divider(height: 24),
                            const Align(alignment: Alignment.centerLeft, child: Text('Chapters', style: TextStyle(fontWeight: FontWeight.bold))),
                            ... ((chaptersAsync.asData?.value ?? <Chapter>[]) .map((ch)=> ChapterTile(
                              chapter: ch,
                              isCurrent: _currentChapter(chaptersAsync.asData?.value ?? [], st.position, svc)?.id == ch.id,
                              onTap: () async {
                                await svc.seekBook(Duration(milliseconds: ch.startMs));
                              },
                            ))),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: ()=> Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator())),
      error: (e,st)=> Scaffold(appBar: AppBar(), body: Center(child: Text('Error: $e'))),
    );
  }

  Chapter? _currentChapter(List<Chapter> chs, Duration pos, dynamic svc) {
    Duration bookPos = Duration.zero;
    try { bookPos = svc.bookPosition as Duration; } catch (_) { bookPos = pos; }
    for (final c in chs) {
      final s = Duration(milliseconds: c.startMs);
      final e = Duration(milliseconds: c.endMs);
      if (bookPos >= s && bookPos < e) return c;
    }
    return chs.isEmpty ? null : chs.first;
  }
}
