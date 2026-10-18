import 'server/remote_library_service.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'listening_stats.dart';
import 'package:path/path.dart' as p;
import 'audio/playback_service.dart';
import 'library_service.dart';
import 'settings_service.dart';
import 'db/app_database.dart';

/// An authenticated loopback endpoint for the desktop CLI. No database is opened
/// by the client, and imported audio is streamed into the app's sandbox first.
class DesktopControlService {
  final LibraryService library;
  final PlaybackService playback;
  final File descriptor;
  final RemoteLibraryService? remote;
  final String _token = base64Url.encode(
    List<int>.generate(32, (_) => Random.secure().nextInt(256)),
  );
  final Map<String, Directory> _batches = {};
  HttpServer? _server;
  StreamSubscription<HttpRequest>? _requests;
  Future<void> _commands = Future.value();

  DesktopControlService({
    required this.library,
    required this.playback,
    required this.descriptor,
    this.remote,
  });

  Future<void> start() async {
    if (_server != null) throw StateError('Desktop control is already running');
    final server = _server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    server.idleTimeout = const Duration(seconds: 30);
    _requests = server.listen((request) {
      // Serialize CLI mutations, including imports and their responses.
      _commands = _commands.then((_) => _handle(request)).catchError((
        Object error,
      ) {
        // A disconnected client must not break the queue for the next command.
        stderr.writeln('Desktop CLI request failed: $error');
      });
    });
    final temporaryDescriptor = File('${descriptor.path}.$pid.tmp');
    try {
      await descriptor.parent.create(recursive: true);
      // Create privately before writing the bearer token.
      await temporaryDescriptor.writeAsString('');
      if (!Platform.isWindows) {
        final result = await Process.run('/bin/chmod', [
          '600',
          temporaryDescriptor.path,
        ]);
        if (result.exitCode != 0) {
          throw FileSystemException(
            'Could not secure CLI descriptor',
            descriptor.path,
          );
        }
      }
      await temporaryDescriptor.writeAsString(
        jsonEncode({'port': server.port, 'token': _token, 'pid': pid}),
        flush: true,
      );
      await temporaryDescriptor.rename(descriptor.path);
    } catch (_) {
      await dispose();
      rethrow;
    } finally {
      if (await temporaryDescriptor.exists()) {
        await temporaryDescriptor.delete();
      }
    }
  }

  Map<String, Object?> _status() {
    final state = playback.state;
    return {
      'bookId': playback.currentBookId,
      'status': state.status.name,
      'positionMs': playback.bookPosition.inMilliseconds,
      'durationMs': playback.bookDuration?.inMilliseconds,
      'trackIndex': state.currentIndex,
      'speed': state.speed,
      'volume': state.volume,
      'error': state.error,
      'sleepRemainingMs': playback.sleepRemaining.inMilliseconds,
      'sleepEndOfChapter': playback.sleepEndOfChapter,
      'waitingForChapterEnd': playback.isWaitingForChapterEnd,
      'audioEffectsSupported': playback.supportsAudioEffects,
      'audioEffectsError': playback.audioEffectsError,
    };
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.headers.contentType = ContentType.json;
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    try {
      if (request.headers.value(HttpHeaders.authorizationHeader) !=
              'Bearer $_token' ||
          request.headers.value('origin') != null) {
        response.statusCode = HttpStatus.forbidden;
        response.write(jsonEncode({'error': 'Unauthorized CLI request'}));
        return;
      }
      if (request.method != 'POST') {
        response.statusCode = HttpStatus.methodNotAllowed;
        response.write(jsonEncode({'error': 'Use POST'}));
        return;
      }
      Object? result;
      if (request.uri.path == '/import') {
        result = await _import(request);
      } else if (request.uri.path == '/command') {
        final bytes = <int>[];
        await for (final chunk in request) {
          bytes.addAll(chunk);
          if (bytes.length > 64 * 1024 * 1024) {
            throw const FormatException('Command is too large');
          }
        }
        final body = jsonDecode(utf8.decode(bytes));
        if (body is! Map<String, dynamic>) {
          throw const FormatException('Expected a command object');
        }
        result = await _command(body);
      } else {
        response.statusCode = HttpStatus.notFound;
        result = {'error': 'Unknown endpoint'};
      }
      response.write(jsonEncode(result));
    } catch (error) {
      response.statusCode = HttpStatus.badRequest;
      response.write(jsonEncode({'error': error.toString()}));
    } finally {
      try {
        await response.close();
      } on IOException {
        // A CLI client can disconnect while a command is completing.
      }
    }
  }

  Future<Object?> _import(HttpRequest request) async {
    final name = request.uri.queryParameters['name'];
    if (name == null ||
        name.isEmpty ||
        p.basename(name) != name ||
        !{
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
          '.mp2',
          '.mov',
          '.webm',
          '.3gp',
          '.mkv',
          '.mka',
        }.contains(p.extension(name).toLowerCase())) {
      throw const FormatException('An audio filename is required');
    }
    final batch = request.uri.queryParameters['batch'];
    if (batch != null && !_batches.containsKey(batch)) {
      throw const FormatException('Unknown import batch');
    }
    final temp = batch == null
        ? await Directory.systemTemp.createTemp('crisper_cli_')
        : _batches[batch]!;
    try {
      var file = File(p.join(temp.path, name));
      var duplicate = 1;
      while (await file.exists()) {
        file = File(
          p.join(
            temp.path,
            '${p.basenameWithoutExtension(name)}_${duplicate++}${p.extension(name)}',
          ),
        );
      }
      final sink = file.openWrite();
      try {
        await sink.addStream(request);
      } finally {
        await sink.close();
      }
      if (await file.length() == 0) {
        throw const FormatException('Audio file is empty');
      }
      if (batch != null) return {'staged': p.basename(file.path)};
      final id = await library.importFiles([file.path]);
      return {'bookId': id};
    } finally {
      if (batch == null) await temp.delete(recursive: true);
    }
  }

  Future<Object?> _command(Map<String, dynamic> args) async {
    final command = args['command'];
    final bookId = args['bookId'];
    switch (command) {
      case 'servers' ||
          'server-connect' ||
          'server-disconnect' ||
          'server-browse' ||
          'server-download':
        final service = remote;
        if (service == null) {
          throw const FormatException('Remote libraries are unavailable');
        }
        await service.init();
        switch (command) {
          case 'server-connect':
            await service.connect(
              name: _string(args, 'name'),
              kind: _string(args, 'kind'),
              url: _string(args, 'url'),
              secret: _string(args, 'secret'),
              username: args['username'] as String? ?? '',
              allowLocalHttp: args['allowLocalHttp'] == true,
            );
          case 'server-disconnect':
            await service.disconnect(_string(args, 'connectionId'));
          case 'server-browse':
            return [
              for (final e in await service.browse(
                _string(args, 'connectionId'),
                args['path'] as String? ?? '',
              ))
                e.toJson(),
            ];
          case 'server-download':
            return {
              'bookId': await service.download(
                _string(args, 'connectionId'),
                _string(args, 'path'),
                _string(args, 'title'),
                author: args['author'] as String? ?? '',
                file: args['file'] == true,
              ),
            };
        }
        return service.status();
      case 'import-begin':
        final id = base64Url.encode(
          List.generate(24, (_) => Random.secure().nextInt(256)),
        );
        _batches[id] = await Directory.systemTemp.createTemp('crisper_batch_');
        return {'batch': id};
      case 'import-commit' || 'import-cancel':
        final batch = args['batch'];
        final directory = _batches.remove(batch);
        if (directory == null) {
          throw const FormatException('Unknown import batch');
        }
        try {
          if (command == 'import-cancel') return {'cancelled': true};
          final paths = await directory
              .list()
              .where((entry) => entry is File)
              .map((entry) => entry.path)
              .toList();
          if (paths.isEmpty) {
            throw const FormatException('No audio files uploaded');
          }
          final title = args['title'];
          final author = args['author'];
          if ((title != null && title is! String) ||
              (author != null && author is! String)) {
            throw const FormatException('Invalid book metadata');
          }
          return {
            'bookId': await library.importFiles(
              paths,
              title: title as String?,
              author: author as String?,
            ),
          };
        } finally {
          await directory.delete(recursive: true);
        }
      case 'book-edit':
        final changes = args['changes'];
        if (changes is! Map<String, dynamic>) {
          throw const FormatException('changes must be an object');
        }
        await playback.updateBookDetails(_bookId(args), changes);
        return (await library.getBook(_bookId(args)))!.toJson();
      case 'book-cover':
        final image = _string(args, 'base64');
        if (image.length > 14 * 1024 * 1024) {
          throw const FormatException('Cover is too large');
        }
        final id = _bookId(args);
        await library.setCover(id, Uint8List.fromList(base64Decode(image)));
        await playback.updateBookDetails(id, {});
        return {'updated': true};
      case 'book-settings':
        final id = _bookId(args);
        if (args.containsKey('values') || args['reset'] == true) {
          final values = args['values'] ?? <String, dynamic>{};
          if (values is! Map<String, dynamic>) {
            throw const FormatException('values must be an object');
          }
          await playback.updateBookPreferences(
            id,
            values,
            reset: args['reset'] == true,
          );
        }
        return library.preferences(id);
      case 'mark':
        await playback.markBook(_bookId(args), _string(args, 'status'));
      case 'refresh-metadata':
        final id = _bookId(args);
        final updated = await library.refreshMetadata(id);
        await playback.updateBookDetails(id, {});
        return {'refreshed': updated};
      case 'queue':
        final entries = await library.db.queue();
        return [
          for (var i = 0; i < entries.length; i++)
            {
              'position': i + 1,
              'book': (await library.getBook(entries[i].bookId))?.toJson(),
            },
        ];
      case 'queue-add':
        final position = args['position'];
        if (position != null && (position is! int || position < 1)) {
          throw const FormatException('position must be a positive integer');
        }
        await playback.enqueue(
          _bookId(args),
          position: position == null ? null : (position as int) - 1,
        );
      case 'queue-remove':
        await playback.removeFromQueue(_bookId(args));
      case 'queue-play':
        await playback.playNextQueued();
      case 'stats':
        return listeningStats(
          await library.db.select(library.db.listeningHistory).get(),
        );
      case 'refresh-chapters':
        return {'refreshed': await playback.refreshChapters(_bookId(args))};
      case 'chapters':
        final id = _bookId(args);
        return [for (final ch in await library.db.chaptersFor(id)) ch.toJson()];
      case 'chapter':
        final id = _bookId(args);
        final chapters = await library.db.chaptersFor(id);
        final index = _number(args, 'index', 1, chapters.length).toInt() - 1;
        if (playback.currentBookId != id) await playback.loadBook(id);
        await playback.seekChapter(chapters[index]);
      case 'next-chapter':
        await playback.nextChapter();
      case 'previous-chapter':
        await playback.previousChapter();
      case 'next':
        await playback.nextTrack();
      case 'previous':
        await playback.previousTrack();
      case 'skip':
        final seconds = _number(args, 'seconds', -86400, 86400).toInt();
        if (seconds >= 0) {
          await playback.skipForward(seconds);
        } else {
          await playback.skipBack(-seconds);
        }
      case 'stop':
        await playback.stop();
      case 'sleep':
        if (args['cancel'] == true) {
          playback.cancelSleepTimer();
        } else {
          final seconds = _number(args, 'seconds', 0, 86400);
          if (playback.currentBookId == null) {
            throw StateError('No book loaded');
          }
          playback.setSleepTimer(
            Duration(milliseconds: (seconds * 1000).round()),
            endOfChapter: args['endOfChapter'] == true,
          );
        }
      case 'bookmark-go' || 'bookmark-edit' || 'bookmark-delete':
        final id = _string(args, 'id');
        final rows = await library.db.select(library.db.bookmarks).get();
        final found = rows.where((row) => row.id == id).firstOrNull;
        if (found == null) throw const FormatException('Unknown bookmark ID');
        if (command == 'bookmark-go') {
          await playback.seekBookmark(found);
        }
        if (command == 'bookmark-edit') {
          await playback.bookmarks.update(
            id,
            _string(args, 'title'),
            args.containsKey('note') ? args['note'] as String? : found.note,
          );
        }
        if (command == 'bookmark-delete') {
          await playback.bookmarks.delete(id);
        }
      case 'history':
        return [
          for (final row
              in bookId == null
                  ? await playback.history.recent()
                  : await playback.history.forBook(_string(args, 'bookId')))
            row.toJson(),
        ];
      case 'clear-history' || 'clear-bookmarks':
        if (args['confirm'] != true) {
          throw const FormatException('Explicit confirmation is required');
        }
        if (command == 'clear-history') {
          await playback.pause();
          await library.db.clearAllHistory();
        } else {
          await library.db.clearAllBookmarks();
        }
        return {'cleared': command};
      case 'export':
        await playback.handleAppPaused();
        return library.db.exportAllJson();
      case 'restore':
        final data = args['data'];
        if (data is! Map<String, dynamic>) {
          throw const FormatException('Expected library JSON');
        }
        await playback.unload();
        await library.db.importAllJson(data);
        return {'restored': true};
      case 'settings':
        final settings = playback.settings;
        if (settings == null) throw StateError('Settings are unavailable');
        if (args.containsKey('key')) _setSetting(settings, args);
        return _settings(settings);
      case 'status':
        return _status();
      case 'list':
        return _listBooks(args);
      case 'load' || 'play':
        if (bookId != null) {
          if (bookId is! String || await library.getBook(bookId) == null) {
            throw const FormatException('Unknown book ID');
          }
          await playback.loadBook(bookId);
        }
        if (playback.currentBookId == null) {
          throw StateError('Load a book with play BOOK_ID first');
        }
        if (command == 'play') await playback.play();
      case 'delete':
        if (bookId is! String || await library.getBook(bookId) == null) {
          throw const FormatException('Unknown book ID');
        }
        await library.deleteBook(bookId);
        return {'deleted': bookId};
      case 'pause':
        await playback.pause();
      case 'seek':
        if (playback.currentBookId == null) throw StateError('No book loaded');
        final seconds = _number(args, 'seconds', 0, 2147483647);
        await playback.seekBook(
          Duration(milliseconds: (seconds * 1000).round()),
        );
      case 'speed':
        await playback.setSpeed(_number(args, 'value', 0.5, 3));
      case 'volume':
        await playback.setVolume(_number(args, 'value', 0, 1));
      case 'bookmark':
        if (playback.currentBookId == null) throw StateError('No book loaded');
        final title = args['title'];
        if (title != null && title is! String) {
          throw const FormatException('Invalid title');
        }
        return {
          'bookmarkId': await playback.addManualBookmark(
            title: title as String?,
            note: args['note'] as String?,
          ),
        };
      case 'bookmarks':
        final id = bookId ?? playback.currentBookId;
        if (id is! String) throw StateError('No book loaded');
        return [
          for (final bookmark in await playback.bookmarks.forBook(id))
            {
              'id': bookmark.id,
              'title': bookmark.title,
              'positionMs': bookmark.bookPositionMs,
              'kind': bookmark.kind,
              'note': bookmark.note,
              'filePath': bookmark.filePath,
            },
        ];
      default:
        throw FormatException('Unknown command: $command');
    }
    return _status();
  }

  Future<List<Map<String, dynamic>>> _listBooks(
    Map<String, dynamic> args,
  ) async {
    final query = args['query'] ?? '';
    final filter = args['filter'] ?? 'all';
    final sort = args['sort'] ?? (filter == 'recent' ? 'lastPlayed' : 'recent');
    if (query is! String ||
        ![
          'all',
          'recent',
          'finished',
          'unfinished',
          'unread',
        ].contains(filter) ||
        ![
          'recent',
          'title',
          'author',
          'series',
          'duration',
          'lastPlayed',
        ].contains(sort)) {
      throw const FormatException('Invalid library query, filter or sort');
    }
    final books = (await library.allBooks())
        .where(
          (book) =>
              (filter != 'finished' || book.isFinished) &&
              (filter != 'unfinished' || !book.isFinished) &&
              (filter != 'unread' ||
                  (!book.isFinished && book.totalProgress == 0)) &&
              (filter != 'recent' || book.lastPlayedAtMs != null) &&
              (args['collection'] == null ||
                  book.collection == args['collection']) &&
              (args['series'] == null || book.series == args['series']) &&
              ('${book.title} ${book.author} ${book.series} ${book.collection}'
                  .toLowerCase()
                  .contains(query.toLowerCase())),
        )
        .toList();
    int compare(Book a, Book b) => switch (sort) {
      'title' => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      'author' => a.author.toLowerCase().compareTo(b.author.toLowerCase()),
      'series' =>
        a.series.toLowerCase() != b.series.toLowerCase()
            ? a.series.toLowerCase().compareTo(b.series.toLowerCase())
            : (a.seriesOrder ?? double.infinity).compareTo(
                b.seriesOrder ?? double.infinity,
              ),
      'duration' => b.totalDurationMs.compareTo(a.totalDurationMs),
      'lastPlayed' => (b.lastPlayedAtMs ?? 0).compareTo(a.lastPlayedAtMs ?? 0),
      _ => b.addedAtMs.compareTo(a.addedAtMs),
    };
    books.sort(compare);
    return [for (final book in books) book.toJson()];
  }

  String _bookId(Map<String, dynamic> args) {
    final id = args['bookId'] ?? playback.currentBookId;
    if (id is! String) {
      throw StateError('Supply a book ID or load a book first');
    }
    return id;
  }

  String _string(Map<String, dynamic> args, String key) {
    final value = args[key];
    if (value is! String || value.isEmpty) {
      throw FormatException('$key is required');
    }
    return value;
  }

  Map<String, Object> _settings(SettingsService s) => {
    'playbackSpeed': s.playbackSpeed,
    'volume': s.volume,
    'skipSilence': s.skipSilence,
    'boostDb': s.boostDb,
    'equalizer': s.equalizer,
    'seekSeconds': s.seekSeconds,
    'smartRewindSeconds': s.smartRewindSeconds,
    'smartRewindAfterSeconds': s.smartRewindAfterSeconds,
    'autoBookmarkEnabled': s.autoBookmarkEnabled,
    'autoBookmarkIntervalSeconds': s.autoBookmarkInterval.inSeconds,
    'sleepTimerDefaultMinutes': s.sleepTimerDefault.inMinutes,
    'themeMode': s.themeMode,
    'resumeOnLaunch': s.resumeOnLaunch,
    'onboardingDone': s.onboardingDone,
  };

  void _setSetting(SettingsService s, Map<String, dynamic> args) {
    final key = _string(args, 'key');
    final value = args['value'];
    switch (key) {
      case 'playbackSpeed':
        s.playbackSpeed = _number(args, 'value', .5, 3);
      case 'boostDb':
        s.boostDb = _number(args, 'value', 0, 12);
      case 'equalizer':
        if (!['off', 'speech', 'warm', 'bass-reduction'].contains(value)) {
          throw const FormatException('Invalid equalizer preset');
        }
        s.equalizer = value as String;
      case 'volume':
        s.volume = _number(args, 'value', 0, 1);
      case 'autoBookmarkIntervalSeconds':
        s.autoBookmarkInterval = Duration(
          seconds: _number(args, 'value', 1, 86400).toInt(),
        );
      case 'sleepTimerDefaultMinutes':
        s.sleepTimerDefault = Duration(
          minutes: _number(args, 'value', 0, 1440).toInt(),
        );
      case 'smartRewindSeconds':
        s.smartRewindSeconds = _number(args, 'value', 0, 60).toInt();
      case 'smartRewindAfterSeconds':
        s.smartRewindAfterSeconds = _number(args, 'value', 0, 86400).toInt();
      case 'seekSeconds':
        if (![10, 15, 30, 60].contains(value)) {
          throw const FormatException('seekSeconds must be 10, 15, 30, or 60');
        }
        s.seekSeconds = value as int;
      case 'themeMode':
        if (!['system', 'light', 'dark'].contains(value)) {
          throw const FormatException('Invalid themeMode');
        }
        s.themeMode = value as String;
      case 'skipSilence' ||
          'autoBookmarkEnabled' ||
          'resumeOnLaunch' ||
          'onboardingDone':
        if (value is! bool) {
          throw const FormatException('Expected true or false');
        }
        switch (key) {
          case 'skipSilence':
            s.skipSilence = value;
          case 'autoBookmarkEnabled':
            s.autoBookmarkEnabled = value;
          case 'resumeOnLaunch':
            s.resumeOnLaunch = value;
          case 'onboardingDone':
            s.onboardingDone = value;
        }
      default:
        throw FormatException('Unknown setting: $key');
    }
  }

  double _number(Map<String, dynamic> args, String key, num min, num max) {
    final value = args[key];
    if (value is! num || !value.isFinite || value < min || value > max) {
      throw FormatException('$key must be between $min and $max');
    }
    return value.toDouble();
  }

  Future<void> dispose() async {
    await _requests?.cancel();
    await _server?.close(force: true);
    _server = null;
    await _commands;
    for (final directory in _batches.values) {
      if (await directory.exists()) await directory.delete(recursive: true);
    }
    _batches.clear();
    if (await descriptor.exists()) {
      try {
        final data = jsonDecode(await descriptor.readAsString());
        if (data is Map && data['token'] == _token) await descriptor.delete();
      } on FormatException {
        // Do not remove another instance's descriptor.
      }
    }
  }
}
