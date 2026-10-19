import 'dart:io';
import 'dart:convert';
import '../models/book_preferences.dart';
import 'audio/audio_metadata.dart';
import 'package:drift/drift.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../utils/format.dart';
import '../utils/folder_import.dart';
import 'audio/chapter_parser.dart';
import 'audio/cover_extractor.dart';
import 'db/app_database.dart';

typedef DurationProbe = Future<Duration?> Function(String path);

class LibraryService {
  final AppDatabase db;
  final Future<Directory> Function() storageDirectory;
  final DurationProbe probeDuration;
  Future<void> Function(String id)? beforeDelete;
  LibraryService(
    this.db, {
    Future<Directory> Function()? storageDirectory,
    DurationProbe? probeDuration,
  }) : storageDirectory = storageDirectory ?? getApplicationSupportDirectory,
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
    // Android document providers commonly label M4B/Opus files as generic
    // binary data. MIME filters disable those rows before we can inspect them.
    final android = defaultTargetPlatform == TargetPlatform.android;
    final files = await FilePicker.pickFiles(
      type: android ? FileType.any : FileType.custom,
      allowedExtensions: android
          ? null
          : [for (final extension in audioExtensions) extension.substring(1)],
    );
    if (files.isEmpty) return [];
    final unsupported = files.where(
      (file) => !audioExtensions.contains(p.extension(file.name).toLowerCase()),
    );
    if (unsupported.isNotEmpty) {
      throw FormatException(
        'Select supported audio files (for example M4B, MP3 or WAV). '
        'Unsupported selection: ${unsupported.take(3).map((file) => file.name).join(', ')}',
      );
    }
    if (files.any((file) => file.path == null)) {
      throw const FileSystemException(
        'The file provider did not make the selected audio available. '
        'Download it to this device and select it again.',
      );
    }
    return files.map((file) => file.path!).toList();
  }

  Future<String?> importFiles(
    List<String> paths, {
    String? title,
    String? author,
    bool preserveOrder = false,
  }) async {
    if (paths.isEmpty) return null;
    if (kIsWeb) {
      throw UnsupportedError('Audio import requires the installed app');
    }
    paths = paths.toSet().toList();
    if (!preserveOrder) paths.sort(_naturalCompare);
    for (final path in paths) {
      if (!await File(path).exists()) {
        throw FileSystemException('Audio file is unavailable', path);
      }
    }
    final id = const Uuid().v4();
    var inferredTitle = title ?? _inferTitle(paths);
    final dir = await _bookDirectory(id);
    await dir.create(recursive: true);
    try {
      final ownedPaths = <String>[];
      for (var i = 0; i < paths.length; i++) {
        final dest = p.join(
          dir.path,
          '${i.toString().padLeft(5, '0')}_${p.basename(paths[i])}',
        );
        await File(paths[i]).copy(dest);
        ownedPaths.add(dest);
      }
      final metadata = await AudioMetadata.read(ownedPaths.first);
      if (title == null && metadata.title != null) {
        inferredTitle = metadata.title!;
      }
      final inferredAuthor = author ?? metadata.author ?? 'Unknown';
      final durations = await _probeDurations(ownedPaths);
      final total = _total(durations);
      var chapters = _chaptersFromTracks(id, ownedPaths, durations);
      String? cover;
      if (ownedPaths.length == 1 &&
          {
            '.m4b',
            '.m4a',
          }.contains(p.extension(ownedPaths.first).toLowerCase())) {
        final parsed = await ChapterParser.parseFile(
          ownedPaths.first,
          totalDuration: total,
        );
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
                trackIndex: const Value(0),
              ),
          ];
        }
        cover = await CoverExtractor.extractCover(
          ownedPaths.first,
          outputDirectory: dir,
        );
      }
      if (ownedPaths.length == 1 && metadata.chapters.isNotEmpty) {
        final parsed = _chapterEndpoints(metadata.chapters, total);
        chapters = [
          for (final chapter in parsed)
            ChaptersCompanion.insert(
              id: const Uuid().v4(),
              bookId: id,
              title: chapter.title,
              startMs: chapter.start.inMilliseconds,
              endMs: chapter.end.inMilliseconds,
              filePath: Value(ownedPaths.single),
              trackIndex: const Value(0),
            ),
        ];
      }
      if (metadata.artwork != null) {
        final ext = AudioMetadata.imageExtension(metadata.artwork!);
        if (ext != null) {
          final image = File(p.join(dir.path, 'cover.$ext'));
          await image.writeAsBytes(metadata.artwork!, flush: true);
          cover = image.path;
        }
      }
      await db.transaction(() async {
        await db.upsertBook(
          BooksCompanion.insert(
            id: id,
            title: inferredTitle,
            author: Value(inferredAuthor),
            coverPath: Value(cover ?? ''),
            filePathsJson: AppDatabase.encodePaths(ownedPaths),
            totalDurationMs: Value(total?.inMilliseconds ?? 0),
            addedAtMs: DateTime.now().millisecondsSinceEpoch,
          ),
        );
        await _saveTracks(id, ownedPaths, durations);
        await db.replaceChapters(id, chapters);
      });
      return id;
    } catch (_) {
      await dir.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> editBook(String id, Map<String, dynamic> changes) async {
    if (await getBook(id) == null) throw StateError('Book not found');
    const keys = {'title', 'author', 'series', 'seriesOrder', 'collection'};
    if (changes.keys.any((k) => !keys.contains(k))) {
      throw const FormatException('Unknown book detail');
    }
    for (final key in ['title', 'author', 'series', 'collection']) {
      if (!changes.containsKey(key)) continue;
      final value = changes[key];
      if (value is! String ||
          value.length > 1000 ||
          (key == 'title' && value.trim().isEmpty)) {
        throw FormatException('Invalid $key');
      }
    }
    final order = changes['seriesOrder'];
    if (order != null && (order is! num || !order.isFinite || order < 0)) {
      throw const FormatException('Invalid seriesOrder');
    }
    await (db.update(db.books)..where((t) => t.id.equals(id))).write(
      BooksCompanion(
        title: changes.containsKey('title')
            ? Value((changes['title'] as String).trim())
            : const Value.absent(),
        author: changes.containsKey('author')
            ? Value((changes['author'] as String).trim())
            : const Value.absent(),
        series: changes.containsKey('series')
            ? Value((changes['series'] as String).trim())
            : const Value.absent(),
        collection: changes.containsKey('collection')
            ? Value((changes['collection'] as String).trim())
            : const Value.absent(),
        seriesOrder: changes.containsKey('seriesOrder')
            ? Value((order as num?)?.toDouble())
            : const Value.absent(),
      ),
    );
  }

  Future<void> setCover(String id, Uint8List image) async {
    if (await getBook(id) == null) throw StateError('Book not found');
    final ext = AudioMetadata.imageExtension(image);
    if (image.length > 10 * 1024 * 1024 || ext == null) {
      throw const FormatException('Cover must be a JPEG or PNG under 10 MB');
    }
    final directory = await _bookDirectory(id);
    await directory.create(recursive: true);
    final file = File(
      p.join(directory.path, 'cover-${const Uuid().v4()}.$ext'),
    );
    try {
      await file.writeAsBytes(image, flush: true);
      await (db.update(db.books)..where((t) => t.id.equals(id))).write(
        BooksCompanion(coverPath: Value(file.path)),
      );
    } catch (_) {
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  Future<bool> refreshMetadata(String id) async {
    final book = await getBook(id);
    if (book == null) throw StateError('Book not found');
    final paths = AppDatabase.decodePaths(book.filePathsJson);
    if (paths.isEmpty) return false;
    final metadata = await AudioMetadata.read(paths.first);
    if (metadata.title == null &&
        metadata.author == null &&
        metadata.artwork == null) {
      return false;
    }
    await editBook(id, {
      if (metadata.title != null) 'title': metadata.title,
      if (metadata.author != null) 'author': metadata.author,
    });
    if (metadata.artwork != null &&
        AudioMetadata.imageExtension(metadata.artwork!) != null) {
      await setCover(id, metadata.artwork!);
    }
    return true;
  }

  Future<Map<String, dynamic>> preferences(String id) async {
    final book = await getBook(id);
    if (book == null) throw StateError('Book not found');
    return BookPreferences.decode(book.playbackPreferencesJson);
  }

  Future<void> setPreferences(
    String id,
    Map<String, dynamic> changes, {
    bool reset = false,
  }) async {
    final current = reset ? <String, dynamic>{} : await preferences(id);
    // Validate patch keys even if the value is null (null removes an override).
    final normalized = BookPreferences.validate({...current, ...changes});
    if (await getBook(id) == null) throw StateError('Book not found');
    await (db.update(db.books)..where((t) => t.id.equals(id))).write(
      BooksCompanion(playbackPreferencesJson: Value(jsonEncode(normalized))),
    );
  }

  static List<ParsedChapter> _chapterEndpoints(
    List<ParsedChapter> chapters,
    Duration? duration,
  ) {
    final sorted =
        chapters.where((c) => duration == null || c.start < duration).toList()
          ..sort((a, b) => a.start.compareTo(b.start));
    return [
      for (var i = 0; i < sorted.length; i++)
        ParsedChapter(
          title: sorted[i].title,
          start: sorted[i].start,
          end: i + 1 < sorted.length
              ? sorted[i + 1].start
              : duration ?? sorted[i].end,
        ),
    ];
  }

  /// Re-read embedded chapters without changing progress, bookmarks or audio.
  /// An absent/unsupported chapter table leaves the existing table intact.
  Future<bool> refreshChapters(String id) async {
    final book = await getBook(id);
    if (book == null) throw StateError('Book not found');
    final paths = AppDatabase.decodePaths(book.filePathsJson);
    if (paths.length != 1) return false;
    final duration = book.totalDurationMs > 0
        ? Duration(milliseconds: book.totalDurationMs)
        : null;
    final parsed =
        {'.m4b', '.m4a'}.contains(p.extension(paths.single).toLowerCase())
        ? await ChapterParser.parseFile(paths.single, totalDuration: duration)
        : _chapterEndpoints(
            (await AudioMetadata.read(paths.single)).chapters,
            duration,
          );
    if (parsed == null || parsed.isEmpty) return false;
    await db.replaceChapters(id, [
      for (final chapter in parsed)
        ChaptersCompanion.insert(
          id: const Uuid().v4(),
          bookId: id,
          title: chapter.title,
          startMs: chapter.start.inMilliseconds,
          endMs: chapter.end.inMilliseconds,
          filePath: Value(paths.single),
          trackIndex: const Value(0),
        ),
    ]);
    return true;
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
          'Book file is missing; re-import the book',
          path,
        );
      }
    }
    // Adopt legacy paths into durable app storage before cache grants expire.
    if (tracks.isEmpty && paths.isNotEmpty) {
      final dir = await _bookDirectory(book.id);
      await dir.create(recursive: true);
      final replacements = <String, String>{};
      for (var i = 0; i < paths.length; i++) {
        final dest = p.join(
          dir.path,
          '${i.toString().padLeft(5, '0')}_${p.basename(paths[i])}',
        );
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
                  book.lastPositionFilePath,
            ),
          ),
        );
        for (final entry in replacements.entries) {
          await (db.update(db.bookmarks)..where(
                (t) => t.bookId.equals(book.id) & t.filePath.equals(entry.key),
              ))
              .write(BookmarksCompanion(filePath: Value(entry.value)));
          await (db.update(db.chapters)..where(
                (t) => t.bookId.equals(book.id) & t.filePath.equals(entry.key),
              ))
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
    String id,
    List<String> paths,
    List<Duration?> durations,
  ) => db.replaceTracks(id, [
    for (var i = 0; i < paths.length; i++)
      BookTracksCompanion.insert(
        bookId: id,
        trackIndex: i,
        filePath: paths[i],
        durationMs: Value(durations[i]?.inMilliseconds),
      ),
  ]);

  Future<void> updateTrackDuration(
    String bookId,
    int index,
    Duration duration,
  ) async {
    await db.transaction(() async {
      final tracks = await db.tracksFor(bookId);
      if (index < 0 || index >= tracks.length || duration <= Duration.zero) {
        return;
      }
      await (db.update(
            db.bookTracks,
          )..where((t) => t.bookId.equals(bookId) & t.trackIndex.equals(index)))
          .write(
            BookTracksCompanion(durationMs: Value(duration.inMilliseconds)),
          );
      final durations = tracks
          .map(
            (t) => t.durationMs == null
                ? null
                : Duration(milliseconds: t.durationMs!),
          )
          .toList();
      durations[index] = duration;
      await _updateTiming(
        bookId,
        tracks.map((t) => t.filePath).toList(),
        durations,
      );
    });
  }

  Future<void> _updateTiming(
    String id,
    List<String> paths,
    List<Duration?> durations,
  ) async {
    final total = _total(durations);
    await (db.update(db.books)..where((t) => t.id.equals(id))).write(
      BooksCompanion(totalDurationMs: Value(total?.inMilliseconds ?? 0)),
    );
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
    String id,
    List<String> paths,
    List<Duration?> durations,
  ) {
    var cursor = 0;
    final chapters = <ChaptersCompanion>[];
    for (var i = 0; i < paths.length; i++) {
      // Unknown timings are represented by zero-length chapters, never invented.
      final end = cursor + (durations[i]?.inMilliseconds ?? 0);
      chapters.add(
        ChaptersCompanion.insert(
          id: const Uuid().v4(),
          bookId: id,
          title: paths.length == 1
              ? 'Chapter 1'
              : titleFromPath(
                  p.basename(paths[i]).replaceFirst(RegExp(r'^\d{5}_'), ''),
                ),
          startMs: cursor,
          endMs: end,
          filePath: Value(paths[i]),
          trackIndex: Value(i),
        ),
      );
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

  static int _naturalCompare(String a, String b) => naturalPathCompare(a, b);

  Future<void> updateProgress(
    String id,
    String file,
    Duration pos,
    Duration bookPos,
    Duration total, {
    bool isPlaying = true,
  }) async {
    final progress = total.inMilliseconds == 0
        ? 0.0
        : (bookPos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final book = await getBook(id);
    if (book == null) return;
    final finished = book.finishedOverride ?? (progress >= 0.99);
    await (db.update(db.books)..where((t) => t.id.equals(id))).write(
      BooksCompanion(
        lastPlayedAtMs: isPlaying
            ? Value(DateTime.now().millisecondsSinceEpoch)
            : const Value.absent(),
        lastPositionFilePath: Value(file),
        lastPositionMs: Value(pos.inMilliseconds),
        totalProgress: Value(finished ? 1 : progress),
        isFinished: Value(finished),
      ),
    );
  }

  Future<List<String>> scanFolder(String folderPath) async =>
      [for (final book in await scanBookFolders(folderPath)) ...book.files]
        ..sort(naturalPathCompare);
}
