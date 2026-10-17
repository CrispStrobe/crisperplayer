import 'dart:io';
import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../utils/format.dart';
import 'audio/chapter_parser.dart';
import 'audio/cover_extractor.dart';
import 'db/app_database.dart';

class LibraryService {
  final AppDatabase db;
  LibraryService(this.db);

  Stream<List<Book>> watchBooks() => db.watchAllBooks();
  Future<List<Book>> allBooks() => db.allBooks;
  Future<Book?> getBook(String id) => db.getBook(id);
  Stream<Book?> watchBook(String id) => db.watchBook(id);

  Future<void> deleteBook(String id) => db.deleteBook(id);

  Future<List<String>> pickAudioFiles() async {
    try {
      final dynamic res = await FilePicker.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: const ['m4b','m4a','mp3','flac','ogg','wav','aac','opus','wma','aiff','aif','mp2','mov','webm','3gp','mkv','mka'],
      );
      if (res == null) return [];
      List<PlatformFile> files;
      if (res is List<PlatformFile>) {
        files = res;
      } else {
        // FilePickerResult case
        try {
          files = (res as dynamic).files as List<PlatformFile>;
        } catch (_) {
          return [];
        }
      }
      return files.where((f)=> f.path != null).map((f)=> f.path!).toList();
    } catch (e) {
      debugPrint('pickAudioFiles failed: $e');
      return [];
    }
  }

  Future<String?> importFiles(List<String> paths, {String? title, String? author}) async {
    if (paths.isEmpty) return null;
    paths = paths.toList()..sort();
    final id = const Uuid().v4();
    final inferredTitle = title ?? _inferTitle(paths);
    final inferredAuthor = author ?? 'Unknown';
    final total = await _probeTotalDuration(paths);
    // Try real chapter table + cover for single-file m4b/m4a
    List<ChaptersCompanion>? realChapters;
    String? coverPath;
    if (paths.length == 1 && _isSingleM4b(paths.first)) {
      try {
        final parsed = await ChapterParser.parseFile(paths.first, totalDuration: total);
        if (parsed != null && parsed.isNotEmpty) {
          realChapters = [
            for (int i = 0; i < parsed.length; i++)
              ChaptersCompanion.insert(
                id: const Uuid().v4(),
                bookId: id,
                title: parsed[i].title,
                startMs: parsed[i].start.inMilliseconds,
                endMs: parsed[i].end.inMilliseconds,
                filePath: Value(paths.first),
                trackIndex: Value(i),
              ),
          ];
          debugPrint('ChapterParser: used ${parsed.length} real chapters for ${paths.first}');
        }
      } catch (e) {
        debugPrint('ChapterParser failed for ${paths.first}: $e');
      }
      try {
        final cover = await CoverExtractor.extractCover(paths.first);
        if (cover != null && cover.isNotEmpty) {
          coverPath = cover;
          debugPrint('CoverExtractor: found cover $cover');
        }
      } catch (e) {
        debugPrint('CoverExtractor failed for ${paths.first}: $e');
      }
    }

    final book = BooksCompanion.insert(
      id: id, title: inferredTitle, author: Value(inferredAuthor),
      filePathsJson: AppDatabase.encodePaths(paths),
      totalDurationMs: Value(total.inMilliseconds),
      addedAtMs: DateTime.now().millisecondsSinceEpoch,
      coverPath: coverPath != null ? Value(coverPath) : const Value.absent(),
    );
    await db.upsertBook(book);
    final chapters = realChapters ?? _chaptersFromFiles(id, paths, total);
    await db.replaceChapters(id, chapters);
    return id;
  }

  bool _isSingleM4b(String path) {
    final ext = p.extension(path).toLowerCase();
    return ext == '.m4b' || ext == '.m4a';
  }

  String _inferTitle(List<String> paths) {
    if (paths.length == 1) return titleFromPath(paths.first);
    final dir = p.dirname(paths.first);
    if (paths.every((f)=> p.dirname(f)==dir)) {
      final folder = p.basename(dir);
      if (folder.isNotEmpty && folder != '.' && folder != '/') return folder;
    }
    return titleFromPath(paths.first);
  }

  Future<Duration> _probeTotalDuration(List<String> paths) async {
    Duration sum = Duration.zero;
    for (final path in paths) {
      try {
        final player = AudioPlayer();
        final d = await player.setFilePath(path).timeout(const Duration(seconds: 4));
        await player.dispose();
        if (d != null) sum += d;
      } catch (e) {
        debugPrint('probe duration failed for $path: $e');
      }
    }
    return sum;
  }

  List<ChaptersCompanion> _chaptersFromFiles(String bookId, List<String> paths, Duration total) {
    Duration cursor = Duration.zero;
    final out = <ChaptersCompanion>[];
    for (int i=0;i<paths.length;i++) {
      final path = paths[i];
      final title = paths.length == 1 ? 'Chapter 1' : titleFromPath(path);
      final dur = total == Duration.zero ? const Duration(minutes: 30) : (i == paths.length-1 ? total - cursor : Duration(milliseconds: total.inMilliseconds ~/ paths.length));
      final start = cursor;
      final end = cursor + dur;
      cursor = end;
      out.add(ChaptersCompanion.insert(
        id: const Uuid().v4(), bookId: bookId, title: title,
        startMs: start.inMilliseconds, endMs: end.inMilliseconds,
        filePath: Value(path), trackIndex: Value(i),
      ));
    }
    return out;
  }

  Future<void> updateProgress(String bookId, String filePath, Duration pos, Duration bookPos, Duration total) async {
    final progress = total.inMilliseconds==0 ? 0.0 : (bookPos.inMilliseconds / total.inMilliseconds).clamp(0.0,1.0);
    await (db.update(db.books)..where((t)=> t.id.equals(bookId))).write(BooksCompanion(
      lastPlayedAtMs: Value(DateTime.now().millisecondsSinceEpoch),
      lastPositionFilePath: Value(filePath),
      lastPositionMs: Value(pos.inMilliseconds),
      totalProgress: Value(progress),
      isFinished: Value(progress >= 0.99),
    ));
  }

  Future<List<String>> scanFolder(String folderPath) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) return [];
    final exts = {'.m4b','.m4a','.mp3','.flac','.ogg','.wav','.aac','.opus','.wma','.aiff','.aif','.mp2'};
    final files = await dir.list(recursive: true).where((e)=> e is File && exts.contains(p.extension(e.path).toLowerCase())).map((e)=> e.path).toList();
    files.sort();
    return files;
  }
}
