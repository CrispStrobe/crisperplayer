import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import 'audio/playback_service.dart';
import 'library_service.dart';

/// An authenticated loopback endpoint for the desktop CLI. No database is opened
/// by the client, and imported audio is streamed into the app's sandbox first.
class DesktopControlService {
  final LibraryService library;
  final PlaybackService playback;
  final File descriptor;
  final String _token = base64Url.encode(
    List<int>.generate(32, (_) => Random.secure().nextInt(256)),
  );
  HttpServer? _server;
  StreamSubscription<HttpRequest>? _requests;
  Future<void> _commands = Future.value();

  DesktopControlService({
    required this.library,
    required this.playback,
    required this.descriptor,
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
          if (bytes.length > 65536) {
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
    final temp = await Directory.systemTemp.createTemp('crisper_cli_');
    try {
      final file = File(p.join(temp.path, name));
      final sink = file.openWrite();
      try {
        await sink.addStream(request);
      } finally {
        await sink.close();
      }
      if (await file.length() == 0) {
        throw const FormatException('Audio file is empty');
      }
      final id = await library.importFiles([file.path]);
      return {'bookId': id};
    } finally {
      await temp.delete(recursive: true);
    }
  }

  Future<Object?> _command(Map<String, dynamic> args) async {
    final command = args['command'];
    final bookId = args['bookId'];
    switch (command) {
      case 'status':
        return _status();
      case 'list':
        return [
          for (final book in await library.allBooks())
            {
              'id': book.id,
              'title': book.title,
              'author': book.author,
              'durationMs': book.totalDurationMs,
              'lastPositionMs': book.lastPositionMs,
            },
        ];
      case 'play':
        if (bookId != null) {
          if (bookId is! String || await library.getBook(bookId) == null) {
            throw const FormatException('Unknown book ID');
          }
          await playback.loadBook(bookId);
        }
        if (playback.currentBookId == null) {
          throw StateError('Load a book with play BOOK_ID first');
        }
        await playback.play();
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
            },
        ];
      default:
        throw FormatException('Unknown command: $command');
    }
    return _status();
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
