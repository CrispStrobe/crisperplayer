import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'db/app_database.dart';

class BookmarkService {
  final AppDatabase db;
  BookmarkService(this.db);

  Stream<List<Bookmark>> watchFor(String bookId) => db.watchBookmarks(bookId);
  Stream<List<Bookmark>> watchAll() => db.watchAllBookmarks();
  Future<List<Bookmark>> forBook(String bookId) => db.bookmarksFor(bookId);

  Future<String> addManual({
    required String bookId,
    required String filePath,
    required Duration position,
    required Duration bookPosition,
    String? title,
    String? note,
    int? chapterIndex,
  }) async {
    final id = const Uuid().v4();
    final t = title?.trim().isNotEmpty == true
        ? title!
        : 'Bookmark @ ${_fmt(position)}';
    await db.insertBookmark(BookmarksCompanion.insert(
      id: id,
      bookId: bookId,
      title: t,
      note: Value(note),
      kind: const Value('manual'),
      filePath: filePath,
      positionMs: position.inMilliseconds,
      bookPositionMs: bookPosition.inMilliseconds,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      chapterIndex: Value(chapterIndex),
    ));
    return id;
  }

  Future<String> addAuto({
    required String bookId,
    required String filePath,
    required Duration position,
    required Duration bookPosition,
  }) async {
    final id = const Uuid().v4();
    await db.insertBookmark(BookmarksCompanion.insert(
      id: id,
      bookId: bookId,
      title: 'Auto ${_fmt(bookPosition)}',
      kind: const Value('auto'),
      filePath: filePath,
      positionMs: position.inMilliseconds,
      bookPositionMs: bookPosition.inMilliseconds,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    ));
    return id;
  }

  Future<void> delete(String id) => db.deleteBookmark(id);
  Future<void> update(String id, String title, String? note) =>
      db.updateBookmark(id, title, note);

  String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  Future<void> pruneAuto(String bookId, {int keep = 20}) async {
    final all = await db.bookmarksFor(bookId);
    final autos = all.where((b) => b.kind == 'auto').toList();
    if (autos.length <= keep) return;
    autos.sort((a, b) => b.createdAtMs.compareTo(a.createdAtMs));
    for (final b in autos.skip(keep)) {
      await db.deleteBookmark(b.id);
    }
  }
}
