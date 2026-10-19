import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:path/path.dart' as p;
import '../../utils/folder_import.dart';
import 'upload_page.dart';

class _IncomingUpload {
  final String id, name;
  final File file;
  final int size;
  int received = 0;
  bool complete = false;
  _IncomingUpload(this.id, this.name, this.file, this.size);
}

/// Foreground-only, upload-only server. Each instance owns a disposable inbox.
class BrowserUploadServer {
  BrowserUploadServer({
    required this.importBook,
    required this.temporaryDirectory,
    this.onChanged,
    this.maxFileBytes = 4 * 1024 * 1024 * 1024,
    this.maxBatchBytes = 20 * 1024 * 1024 * 1024,
  });

  final Future<String?> Function(List<String> paths, String? title) importBook;
  final Future<Directory> Function() temporaryDirectory;
  final void Function()? onChanged;
  String phase = 'stopped';
  String? currentFilename;
  int receivedBytes = 0;
  int expectedBytes = 0;
  int importedBooks = 0;
  int get stagedFiles => _files.length;
  final Stopwatch _clock = Stopwatch()..start();
  int _lastNotification = 0;
  void _changed({bool force = false}) {
    if (force || _clock.elapsedMilliseconds - _lastNotification >= 200) {
      _lastNotification = _clock.elapsedMilliseconds;
      onChanged?.call();
    }
  }

  final int maxFileBytes;
  final int maxBatchBytes;
  final String accessCode = List.generate(
    20,
    (_) => Random.secure().nextInt(256),
  ).map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  HttpServer? _server;
  Directory? _inbox;
  final Map<String, String> _files = {};
  final Set<String> _hosts = {};
  int _bytes = 0;
  int _reserved = 0;
  final Map<String, _IncomingUpload> _uploads = {};
  final Set<String> _completedImports = {};
  bool _busy = false;
  bool _stopping = false;
  Future<void>? _active;
  Future<void>? _stopFuture;
  Future<void>? _startFuture;
  List<String> addresses = [];
  int get port => _server?.port ?? 0;

  static bool _private(InternetAddress ip) {
    if (ip.isLoopback) return true;
    final b = ip.rawAddress;
    return ip.type == InternetAddressType.IPv4 &&
        (b[0] == 10 ||
            b[0] == 192 && b[1] == 168 ||
            b[0] == 172 && b[1] >= 16 && b[1] <= 31 ||
            b[0] == 169 && b[1] == 254);
  }

  Future<void> start({InternetAddress? bindAddress}) {
    if (_startFuture != null || _stopping) {
      throw StateError('Server already used');
    }
    return _startFuture = _start(bindAddress);
  }

  Future<void> _start(InternetAddress? bindAddress) async {
    if (_server != null || _stopping) throw StateError('Server already used');
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    final ips = interfaces
        .expand((i) => i.addresses)
        .where(_private)
        .map((ip) => ip.address)
        .toSet();
    ips.add('127.0.0.1');
    _inbox = await (await temporaryDirectory()).createTemp('browser-upload-');
    try {
      if (_stopping) throw StateError('Sharing stopped');
      _server = await HttpServer.bind(
        bindAddress ?? InternetAddress.anyIPv4,
        0,
      );
      if (_stopping) throw StateError('Sharing stopped');
      _server!.idleTimeout = const Duration(seconds: 30);
      _hosts.addAll(ips.map((ip) => '$ip:$port'));
      addresses = ips
          .where((ip) => ip != '127.0.0.1')
          .map((ip) => 'http://$ip:$port')
          .toList();
      if (bindAddress?.isLoopback == true) {
        addresses = ['http://127.0.0.1:$port'];
      }
      phase = 'ready';
      _changed(force: true);
      _server!.listen((request) {
        unawaited(_handle(request));
      });
    } catch (_) {
      await _server?.close(force: true);
      _server = null;
      if (await _inbox!.exists()) await _inbox!.delete(recursive: true);
      rethrow;
    }
  }

  void _reply(HttpRequest request, int status, Map<String, Object?> body) {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    response.persistentConnection = false;
    response.headers.set('Cache-Control', 'no-store');
    response.headers.set('X-Content-Type-Options', 'nosniff');
    response.headers.set('Referrer-Policy', 'no-referrer');
    response.headers.set(
      'Content-Security-Policy',
      "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; connect-src 'self'; frame-ancestors 'none'; form-action 'none'",
    );
    try {
      final host = request.headers.value('host');
      final origin = request.headers.value('origin');
      if (_stopping ||
          !_private(request.connectionInfo!.remoteAddress) ||
          !_hosts.contains(host) ||
          (origin != null && origin != 'http://$host')) {
        _reply(request, 403, {'error': 'Local connections only'});
      } else if (request.method == 'GET' && request.uri.path == '/') {
        response.headers.contentType = ContentType.html;
        response.write(uploadPage);
      } else if (request.headers.value('authorization') !=
          'Bearer $accessCode') {
        _reply(request, 401, {
          'error': 'Enter the access code shown in the app',
        });
      } else if (_busy) {
        _reply(request, 409, {
          'error': 'Another transfer or import is in progress',
        });
      } else {
        _busy = true;
        final operation = _perform(request);
        _active = operation;
        try {
          await operation;
        } finally {
          _busy = false;
          _active = null;
        }
      }
    } catch (_) {
      phase = 'error';
      _changed(force: true);
      // No filesystem paths, provider details or parser exceptions leave the app.
      try {
        _reply(request, 500, {
          'error': 'Transfer failed; retry or restart sharing',
        });
      } catch (_) {
        /* Client may have disconnected. */
      }
    } finally {
      try {
        await response.close();
      } catch (_) {
        /* Disconnected client. */
      }
    }
  }

  Future<void> _discardUpload(String name) async {
    final old = _uploads.values.where((u) => u.name == name).toList();
    for (final upload in old) {
      _uploads.remove(upload.id);
      if (!upload.complete) {
        _reserved -= upload.size;
        if (await upload.file.exists()) await upload.file.delete();
      }
    }
  }

  bool _validName(String name) =>
      name.isNotEmpty &&
      name.length <= 200 &&
      !name.contains('/') &&
      !name.contains('\\') &&
      !name.contains('..') &&
      !RegExp(r'[<>:"|?*]').hasMatch(name) &&
      !name.endsWith('.') &&
      !name.endsWith(' ') &&
      !name.runes.any((c) => c < 32 || c == 127) &&
      audioExtensions.contains(p.extension(name).toLowerCase());

  Future<void> _perform(HttpRequest request) async {
    if (request.uri.path == '/upload' && request.method == 'POST') {
      final name = request.uri.queryParameters['name'] ?? '';
      final size = int.tryParse(request.uri.queryParameters['size'] ?? '') ?? 0;
      if (!_validName(name)) {
        _reply(request, 400, {
          'error': 'Choose an audio file with a valid filename',
        });
        return;
      }
      final existing = _files[name];
      final oldLength = existing == null ? 0 : await File(existing).length();
      final sameName = _uploads.values.where((u) => u.name == name).firstOrNull;
      final previousReservation = sameName != null && !sameName.complete
          ? sameName.size
          : 0;
      final names = {..._files.keys, ..._uploads.values.map((u) => u.name)};
      if (size <= 0 ||
          size > maxFileBytes ||
          _bytes - oldLength + _reserved - previousReservation + size >
              maxBatchBytes ||
          (!names.contains(name) && names.length >= 500)) {
        _reply(request, 413, {'error': 'File or book transfer limit exceeded'});
        return;
      }
      await _discardUpload(name);
      if (existing != null) {
        await File(existing).delete();
        _files.remove(name);
        _bytes -= oldLength;
      }
      final id = List.generate(
        20,
        (_) => Random.secure().nextInt(256),
      ).map((n) => n.toRadixString(16).padLeft(2, '0')).join();
      final directory = await _inbox!.createTemp('chunks-');
      final upload = _IncomingUpload(
        id,
        name,
        File(p.join(directory.path, name)),
        size,
      );
      _uploads[id] = upload;
      _reserved += size;
      await upload.file.create();
      _reply(request, 200, {'id': id, 'offset': 0, 'complete': false});
      return;
    }
    if (request.uri.path == '/upload' &&
        (request.method == 'GET' || request.method == 'PATCH')) {
      final upload = _uploads[request.uri.queryParameters['id']];
      if (upload == null) {
        _reply(request, 404, {
          'error': 'Upload expired; select the files again',
        });
        return;
      }
      if (request.method == 'GET') {
        _reply(request, 200, {
          'id': upload.id,
          'offset': upload.received,
          'complete': upload.complete,
        });
        return;
      }
      final offset = int.tryParse(request.uri.queryParameters['offset'] ?? '');
      final length = request.contentLength;
      if (upload.complete || offset != upload.received) {
        _reply(request, 409, {
          'error': 'Upload position changed; retry to resume',
        });
        return;
      }
      if (length <= 0 ||
          length > 8 * 1024 * 1024 ||
          offset! + length > upload.size) {
        _reply(request, 413, {'error': 'Invalid upload chunk size'});
        return;
      }
      phase = 'receiving';
      currentFilename = upload.name;
      receivedBytes = offset;
      expectedBytes = upload.size;
      _changed(force: true);
      final sink = upload.file.openWrite(mode: FileMode.append);
      var received = 0;
      var committed = false;
      try {
        await for (final chunk in request.timeout(
          const Duration(seconds: 120),
        )) {
          received += chunk.length;
          if (_stopping || received > length) throw const FormatException();
          sink.add(chunk);
          await sink.flush();
          receivedBytes = offset + received;
          _changed();
        }
        await sink.close();
        if (_stopping || received != length) throw const FormatException();
        upload.received += received;
        upload.complete = upload.received == upload.size;
        if (upload.complete) {
          _files[upload.name] = upload.file.path;
          _reserved -= upload.size;
          _bytes += upload.size;
        }
        committed = true;
        phase = 'ready';
        _changed(force: true);
        _reply(request, 200, {
          'offset': upload.received,
          'complete': upload.complete,
        });
      } finally {
        if (!committed) {
          try {
            await sink.close();
          } catch (_) {
            /* Disconnected stream. */
          }
          final file = await upload.file.open(mode: FileMode.append);
          try {
            await file.truncate(offset);
          } finally {
            await file.close();
          }
          receivedBytes = offset;
        }
      }
      return;
    }
    if (request.method == 'PUT' && request.uri.path == '/upload') {
      final name = request.uri.queryParameters['name'] ?? '';
      if (!_validName(name)) {
        _reply(request, 400, {
          'error': 'Choose an audio file with a valid filename',
        });
        return;
      }
      final length = request.contentLength;
      final oldLength = _files[name] == null
          ? 0
          : await File(_files[name]!).length();
      final previous = _uploads.values.where((u) => u.name == name).firstOrNull;
      final reservation = previous != null && !previous.complete
          ? previous.size
          : 0;
      final names = {..._files.keys, ..._uploads.values.map((u) => u.name)};
      if (length <= 0 ||
          length > maxFileBytes ||
          _bytes - oldLength + _reserved - reservation + length >
              maxBatchBytes ||
          (!names.contains(name) && names.length >= 500)) {
        _reply(request, 413, {
          'error':
              'Transfer limit exceeded (4 GiB/file, 20 GiB/book, 500 files)',
        });
        return;
      }
      // Filenames select no directories; each track has a generated private
      // directory. Keep the original basename for normal metadata import.
      await _discardUpload(name);
      phase = 'receiving';
      currentFilename = name;
      receivedBytes = 0;
      expectedBytes = length;
      _changed(force: true);
      final partial = File(p.join(_inbox!.path, 'incoming.part'));
      final sink = partial.openWrite();
      var received = 0;
      var succeeded = false;
      try {
        await for (final chunk in request.timeout(
          const Duration(seconds: 120),
        )) {
          received += chunk.length;
          if (_stopping || received > length) throw const FormatException();
          sink.add(chunk);
          // Await flush to keep writes bounded for multi-gigabyte files.
          await sink.flush();
          receivedBytes = received;
          _changed();
        }
        await sink.close();
        if (received != length || _stopping) throw const FormatException();
        final directory = await _inbox!.createTemp('track-');
        final destination = p.join(directory.path, name);
        await partial.rename(destination);
        final previous = _files[name];
        _files[name] = destination;
        _bytes += received - oldLength;
        if (previous != null) await File(previous).delete();
        succeeded = true;
        phase = 'ready';
        _changed(force: true);
        _reply(request, 200, {'uploaded': name, 'files': _files.length});
      } finally {
        if (!succeeded) {
          try {
            await sink.close();
          } catch (_) {
            /* Failed transfer. */
          }
          if (await partial.exists()) await partial.delete();
        }
      }
    } else if (request.uri.path == '/import' &&
        (request.method == 'GET' || request.method == 'POST')) {
      final operation = request.uri.queryParameters['operation'];
      if (operation != null &&
          !RegExp(r'^[a-z0-9-]{10,100}$').hasMatch(operation)) {
        _reply(request, 400, {'error': 'Invalid import operation'});
        return;
      }
      if (request.method == 'GET') {
        _reply(request, 200, {
          'imported':
              operation != null && _completedImports.contains(operation),
        });
        return;
      }
      if (operation != null && _completedImports.contains(operation)) {
        _reply(request, 200, {'imported': true});
        return;
      }
      if (_uploads.values.any((u) => !u.complete)) {
        _reply(request, 409, {
          'error': 'Finish or restart incomplete file uploads before importing',
        });
        return;
      }
      if (_files.isEmpty) {
        _reply(request, 400, {'error': 'Upload audio files first'});
        return;
      }
      final title = request.uri.queryParameters['title']?.trim();
      if (title != null && title.length > 200) {
        _reply(request, 400, {'error': 'Title is too long'});
        return;
      }
      phase = 'importing';
      _changed(force: true);
      final names = _files.keys.toList()..sort(naturalPathCompare);
      final id = await importBook([
        for (final name in names) _files[name]!,
      ], title == null || title.isEmpty ? null : title);
      if (id == null) throw StateError('Import did not create a book');
      if (operation != null) _completedImports.add(operation);
      for (final path in _files.values) {
        await File(path).delete();
      }
      _files.clear();
      _uploads.clear();
      _reserved = 0;
      _bytes = 0;
      importedBooks++;
      phase = 'ready';
      currentFilename = null;
      receivedBytes = expectedBytes = 0;
      _changed(force: true);
      _reply(request, 200, {'imported': true});
    } else {
      _reply(request, 404, {'error': 'Unknown request'});
    }
  }

  Future<void> stop() => _stopFuture ??= _stop();
  Future<void> _stop() async {
    _stopping = true;
    phase = 'stopping';
    _changed(force: true);
    try {
      await _startFuture;
    } catch (_) {
      /* Failed or interrupted start. */
    }
    await _server?.close(force: true);
    _server = null;
    try {
      await _active;
    } catch (_) {
      /* Failed or interrupted transfer. */
    }
    if (_inbox != null && await _inbox!.exists()) {
      await _inbox!.delete(recursive: true);
    }
    _files.clear();
    _uploads.clear();
    _completedImports.clear();
    _reserved = 0;
    _bytes = 0;
    addresses = [];
    phase = 'stopped';
    _changed(force: true);
  }
}
