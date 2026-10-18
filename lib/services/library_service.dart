import 'dart:io';
import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../utils/format.dart';
import 'audio/chapter_parser.dart';
import 'audio/cover_extractor.dart';
import 'db/app_database.dart';

typedef DurationProbe = Future<Duration?> Function(String path);

class LibraryService {
  final AppDatabase db;
  final Future<Directory> Function() storageDirectory;
  final DurationProbe probeDuration;
  Future<void> Function(String id)? beforeDelete;
  LibraryService(this.db,
      {Future<Directory> Function()? storageDirectory,
      DurationProbe? probeDuration})
      : storageDirectory = storageDirectory ?? getApplicationSupportDirectory,
        probeDuration = probeDuration ?? _probeDuration;

  Stream<List<Book>> watchBooks() => db.watchAllBooks();
  Future<List<Book>> allBooks() => db.allBooks;
  Future<Book?> getBook(String id) => db.getBook(id);
  Stream<Book?> watchBook(String id) => db.watchBook(id);

  Future<Directory> _bookDirectory(String id) async {
    // IDs from backups are untrusted and must never become arbitrary paths.
    if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(id)) {
      throw const FormatException('Invalid book ID');
    }
    return Directory(p.join((await storageDirectory()).path, 'library', id));
  }

  Future<void> deleteBook(String id) async {
    await beforeDelete?.call(id);
    await db.transaction(() async {
      await db.clearHistoryForBook(id);
      await db.clearBookmarksForBook(id);
      await (db.delete(db.chapters)..where((t) => t.bookId.equals(id))).go();
      await (db.delete(db.bookTracks)..where((t) => t.bookId.equals(id))).go();
      await db.deleteBook(id);
    });
    final dir = await _bookDirectory(id);
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  Future<List<String>> pickAudioFiles() async {
    if (kIsWeb) {
      throw UnsupportedError('Audio import requires the installed app');
    }
    final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'm4b',
          'm4a',
          'mp3',
          'flac',
          'ogg',
          'wav',
          'aac',
          'opus',
          'wma',
          'aiff',
          'aif',
          'mp2',
          'mov',
          'webm',
          '3gp',
          'mkv',
          'mka'
        ]);
    return files.where((f) => f.path != null).map((f) => f.path!).toList();
  }

  Future<String?> importFiles(List<String> paths,
      {String? title, String? author}) async {
    if (paths.isEmpty) return null;
    if (kIsWeb) {
      throw UnsupportedError('Audio import requires the installed app');
    }
    paths = paths.toSet().toList()..sort(_naturalCompare);
    for (final path in paths) {
      if (!await File(path).exists()) {
        throw FileSystemException('Audio file is unavailable', path);
      }
    }
    final id = const Uuid().v4();
    final inferredTitle = title ?? _inferTitle(paths);
    final dir = await _bookDirectory(id);
    await dir.create(recursive: true);
    try {
      final ownedPaths = <String>[];
      for (var i = 0; i < paths.length; i++) {
        final dest = p.join(dir.path,
            '${i.toString().padLeft(5, '0')}_${p.basename(paths[i])}');
        await File(paths[i]).copy(dest);
        ownedPaths.add(dest);
      }
      final durations = await _probeDurations(ownedPaths);
      final total = _total(durations);
      var chapters = _chaptersFromTracks(id, ownedPaths, durations);
      String? cover;
      if (ownedPaths.length == 1 &&
          {'.m4b', '.m4a'}
              .contains(p.extension(ownedPaths.first).toLowerCase())) {
        final parsed = await ChapterParser.parseFile(ownedPaths.first,
            totalDuration: total);
        if (parsed != null && parsed.isNotEmpty) {
          chapters = [
            for (final chapter in parsed)
              ChaptersCompanion.insert(
                  id: const Uuid().v4(),
                  bookId: id,
                  title: chapter.title,
                  startMs: chapter.start.inMilliseconds,
                  endMs: chapter.end.inMilliseconds,
                  filePath: Value(ownedPaths.first),
                  trackIndex: const Value(0))
          ];
        }
        cover = await CoverExtractor.extractCover(ownedPaths.first,
            outputDirectory: dir);
      }
      await db.transaction(() async {
        await db.upsertBook(BooksCompanion.insert(
            id: id,
            title: inferredTitle,
            author: Value(author ?? 'Unknown'),
            coverPath: Value(cover ?? ''),
            filePathsJson: AppDatabase.encodePaths(ownedPaths),
            totalDurationMs: Value(total?.inMilliseconds ?? 0),
            addedAtMs: DateTime.now().millisecondsSinceEpoch));
        await _saveTracks(id, ownedPaths, durations);
        await db.replaceChapters(id, chapters);
      });
      return id;
    } catch (_) {
      await dir.delete(recursive: true);
      rethrow;
    }
  }

  /// Version-one libraries have no track rows. Probe their actual files rather
  /// than trusting the old equal-duration chapter estimates.
  Future<List<BookTrack>> ensureTracks(Book book) async {
    var tracks = await db.tracksFor(book.id);
    if (tracks.isNotEmpty && tracks.every((t) => t.durationMs != null)) {
      return tracks;
    }
    var paths = AppDatabase.decodePaths(book.filePathsJson);
    for (final path in paths) {
      if (!await File(path).exists()) {
        throw FileSystemException(
            'Book file is missing; re-import the book', path);
      }
    }
    // Adopt legacy paths into durable app storage before cache grants expire.
    if (tracks.isEmpty && paths.isNotEmpty) {
      final dir = await _bookDirectory(book.id);
      await dir.create(recursive: true);
      final replacements = <String, String>{};
      for (var i = 0; i < paths.length; i++) {
        final dest = p.join(dir.path,
            '${i.toString().padLeft(5, '0')}_${p.basename(paths[i])}');
        if (p.normalize(paths[i]) != p.normalize(dest)) {
          await File(paths[i]).copy(dest);
        }
        replacements[paths[i]] = dest;
      }
      var cover = book.coverPath;
      if (cover.isNotEmpty && await File(cover).exists()) {
        final dest = p.join(dir.path, 'cover${p.extension(cover)}');
        if (p.normalize(cover) != p.normalize(dest)) {
          await File(cover).copy(dest);
        }
        cover = dest;
      }
      paths = paths.map((path) => replacements[path]!).toList();
      await db.transaction(() async {
        await (db.update(db.books)..where((t) => t.id.equals(book.id))).write(
            BooksCompanion(
                filePathsJson: Value(AppDatabase.encodePaths(paths)),
                coverPath: Value(cover),
                lastPositionFilePath: Value(
                    replacements[book.lastPositionFilePath] ??
                        book.lastPositionFilePath)));
        for (final entry in replacements.entries) {
          await (db.update(db.bookmarks)
                ..where((t) =>
                    t.bookId.equals(book.id) & t.filePath.equals(entry.key)))
              .write(BookmarksCompanion(filePath: Value(entry.value)));
          await (db.update(db.chapters)
                ..where((t) =>
                    t.bookId.equals(book.id) & t.filePath.equals(entry.key)))
              .write(ChaptersCompanion(filePath: Value(entry.value)));
        }
      });
    }
    final durations = await _probeDurations(paths);
    await db.transaction(() async {
      await _saveTracks(book.id, paths, durations);
      await _updateTiming(book.id, paths, durations);
    });
    tracks = await db.tracksFor(book.id);
    return tracks;
  }

  Future<void> _saveTracks(
          String id, List<String> paths, List<Duration?> durations) =>
      db.replaceTracks(id, [
        for (var i = 0; i < paths.length; i++)
          BookTracksCompanion.insert(
              bookId: id,
              trackIndex: i,
              filePath: paths[i],
              durationMs: Value(durations[i]?.inMilliseconds))
      ]);

  Future<void> updateTrackDuration(
      String bookId, int index, Duration duration) async {
    await db.transaction(() async {
      final tracks = await db.tracksFor(bookId);
      if (index < 0 || index >= tracks.length || duration <= Duration.zero) {
        return;
      }
      await (db.update(db.bookTracks)
            ..where(
                (t) => t.bookId.equals(bookId) & t.trackIndex.equals(index)))
          .write(
              BookTracksCompanion(durationMs: Value(duration.inMilliseconds)));
      final durations = tracks
          .map((t) => t.durationMs == null
              ? null
              : Duration(milliseconds: t.durationMs!))
          .toList();
      durations[index] = duration;
      await _updateTiming(
          bookId, tracks.map((t) => t.filePath).toList(), durations);
    });
  }

  Future<void> _updateTiming(
      String id, List<String> paths, List<Duration?> durations) async {
    final total = _total(durations);
    await (db.update(db.books)..where((t) => t.id.equals(id))).write(
        BooksCompanion(totalDurationMs: Value(total?.inMilliseconds ?? 0)));
    final chapters = await db.chaptersFor(id);
    if (paths.length > 1 || chapters.length <= 1) {
      await db.replaceChapters(id, _chaptersFromTracks(id, paths, durations));
    } else if (total != null && chapters.isNotEmpty) {
      // Preserve embedded chapter boundaries, updating only the final endpoint.
      await (db.update(db.chapters)
            ..where((t) => t.id.equals(chapters.last.id)))
          .write(ChaptersCompanion(endMs: Value(total.inMilliseconds)));
    }
  }

  Future<List<Duration?>> _probeDurations(List<String> paths) async {
    final durations = <Duration?>[];
    for (final path in paths) {
      try {
        final d = await probeDuration(path);
        durations.add(d != null && d > Duration.zero ? d : null);
      } catch (e) {
        debugPrint('Duration unavailable for $path: $e');
        durations.add(null);
      }
    }
    return durations;
  }

  static Future<Duration?> _probeDuration(String path) async {
    final player = AudioPlayer();
    try {
      return await player
          .setFilePath(path)
          .timeout(const Duration(seconds: 15));
    } finally {
      await player.dispose();
    }
  }

  Duration? _total(List<Duration?> durations) => durations.any((d) => d == null)
      ? null
      : durations.fold<Duration>(Duration.zero, (total, d) => total + d!);

  List<ChaptersCompanion> _chaptersFromTracks(
      String id, List<String> paths, List<Duration?> durations) {
    var cursor = 0;
    final chapters = <ChaptersCompanion>[];
    for (var i = 0; i < paths.length; i++) {
      // Unknown timings are represented by zero-length chapters, never invented.
      final end = cursor + (durations[i]?.inMilliseconds ?? 0);
      chapters.add(ChaptersCompanion.insert(
          id: const Uuid().v4(),
          bookId: id,
          title: paths.length == 1
              ? 'Chapter 1'
              : titleFromPath(
                  p.basename(paths[i]).replaceFirst(RegExp(r'^\d{5}_'), '')),
          startMs: cursor,
          endMs: end,
          filePath: Value(paths[i]),
          trackIndex: Value(i)));
      cursor = end;
    }
    return chapters;
  }

  String _inferTitle(List<String> paths) {
    if (paths.length == 1) return titleFromPath(paths.first);
    final dir = p.dirname(paths.first);
    return paths.every((f) => p.dirname(f) == dir)
        ? p.basename(dir)
        : titleFromPath(paths.first);
  }

  static int _naturalCompare(String a, String b) {
    final parts = RegExp(r'\d+|\D+');
    final aa = parts.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
    final bb = parts.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
    for (var i = 0; i < aa.length && i < bb.length; i++) {
      final an = int.tryParse(aa[i]);
      final bn = int.tryParse(bb[i]);
      final cmp =
          an != null && bn != null ? an.compareTo(bn) : aa[i].compareTo(bb[i]);
      if (cmp != 0) return cmp;
    }
    return aa.length.compareTo(bb.length);
  }

  Future<void> updateProgress(String id, String file, Duration pos,
      Duration bookPos, Duration total) async {
    final progress = total.inMilliseconds == 0
        ? 0.0
        : (bookPos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    await (db.update(db.books)..where((t) => t.id.equals(id))).write(
        BooksCompanion(
            lastPlayedAtMs: Value(DateTime.now().millisecondsSinceEpoch),
            lastPositionFilePath: Value(file),
            lastPositionMs: Value(pos.inMilliseconds),
            totalProgress: Value(progress),
            isFinished: Value(progress >= 0.99)));
  }

  Future<List<String>> scanFolder(String folderPath) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) return [];
    const exts = {
      '.m4b',
      '.m4a',
      '.mp3',
      '.flac',
      '.ogg',
      '.wav',
      '.aac',
      '.opus',
      '.wma',
      '.aiff',
      '.aif',
      '.mp2'
    };
    final files = await dir
        .list(recursive: true)
        .where((e) =>
            e is File && exts.contains(p.extension(e.path).toLowerCase()))
        .map((e) => e.path)
        .toList();
    return files..sort(_naturalCompare);
  }
}
