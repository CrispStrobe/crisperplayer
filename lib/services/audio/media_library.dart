import 'dart:io';
import 'package:audio_service/audio_service.dart';
import '../db/app_database.dart';
import 'playback_service.dart';

/// A bounded browse tree shared by car interfaces, widgets and Watch controls.
class MediaLibrary {
  final AppDatabase db;
  final PlaybackService playback;
  MediaLibrary(this.db, this.playback);
  static const root = 'root';
  static const limit = 100;
  MediaItem _book(Book book, {bool playable = false}) => MediaItem(
    id: 'book/${book.id}',
    title: book.title,
    artist: book.author,
    duration: book.totalDurationMs > 0
        ? Duration(milliseconds: book.totalDurationMs)
        : null,
    artUri: book.coverPath.isEmpty ? null : Uri.file(book.coverPath),
    playable: playable,
    extras: {'bookId': book.id, 'isBrowsable': !playable},
  );
  Future<List<MediaItem>> children(String parent) async {
    if (parent == root || parent == AudioService.browsableRootId) {
      return [
        for (final item in [
          ('continue', 'Continue listening'),
          ('library', 'Library'),
          ('up-next', 'Up next'),
        ])
          MediaItem(id: item.$1, title: item.$2, playable: false),
      ];
    }
    if (parent == 'library' || parent == 'continue' || parent == 'up-next') {
      final books = await db.allBooks;
      if (parent == 'continue') {
        books.removeWhere((b) => b.lastPlayedAtMs == null || b.isFinished);
        books.sort((a, b) => b.lastPlayedAtMs!.compareTo(a.lastPlayedAtMs!));
      } else if (parent == 'up-next') {
        final byId = {for (final b in books) b.id: b};
        return [
          for (final entry in (await db.queue()).take(limit))
            if (byId[entry.bookId] != null) _book(byId[entry.bookId]!),
        ];
      } else {
        books.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
      }
      return books.take(limit).map(_book).toList();
    }
    if (parent.startsWith('book/')) {
      final book = await db.getBook(parent.substring(5));
      if (book == null) return [];
      return [
        MediaItem(
          id: 'resume/${book.id}',
          title: 'Resume ${book.title}',
          artist: book.author,
        ),
        MediaItem(
          id: 'chapters/${book.id}',
          title: 'Chapters',
          playable: false,
        ),
      ];
    }
    if (parent.startsWith('chapters/')) {
      final id = parent.substring(9);
      final chapters = await db.chaptersFor(id);
      return [
        for (var i = 0; i < chapters.length && i < limit; i++)
          MediaItem(
            id: 'chapter/$id/$i',
            title: chapters[i].title,
            duration: Duration(
              milliseconds: (chapters[i].endMs - chapters[i].startMs).clamp(
                0,
                1 << 53,
              ),
            ),
          ),
      ];
    }
    return [];
  }

  Future<List<MediaItem>> search(String query) async {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return [];
    return (await db.allBooks)
        .where((b) => '${b.title} ${b.author}'.toLowerCase().contains(needle))
        .take(limit)
        .map((b) => _book(b, playable: true))
        .toList();
  }

  Future<void> play(String mediaId) async {
    final segments = mediaId.split('/');
    if (segments.length == 2 && {'book', 'resume'}.contains(segments[0])) {
      await playback.loadBook(segments[1], autoPlay: true);
    } else if (segments.length == 3 && segments[0] == 'chapter') {
      final chapters = await db.chaptersFor(segments[1]);
      final index = int.tryParse(segments[2]);
      if (index == null || index < 0 || index >= chapters.length) {
        throw const FormatException('Chapter not found');
      }
      await playback.seekChapter(chapters[index]);
      await playback.play();
    } else {
      throw const FormatException('Media item not found');
    }
  }

  static Map<String, Object?> encode(MediaItem item) => {
    'id': item.id,
    'title': item.title,
    'subtitle': item.artist ?? '',
    'playable': item.playable,
    if (item.artUri?.scheme == 'file')
      'artwork': File.fromUri(item.artUri!).path,
  };
}
