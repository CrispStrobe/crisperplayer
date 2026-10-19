import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../db/app_database.dart';
import '../library_service.dart';
import '../server/remote_client.dart';
import '../server/remote_library_service.dart';

/// A durable, opt-in three-way merge. Concurrent progress is presented for a
/// decision; neither the largest offset nor the latest device clock wins.
class PlexProgressService extends ChangeNotifier {
  final LibraryService library;
  final RemoteLibraryService remote;
  final bool Function(String) isBookOpen;
  final Map<String, dynamic> _records = {};
  final Set<String> _enabled = {};
  final Map<String, String> issues = {};
  final Set<String> conflicts = {};
  Future<void>? _loading;
  Future<void> _pending = Future.value();
  Timer? _timer;
  bool _automaticRunning = false;
  bool _disposed = false;
  PlexProgressService(
    this.library,
    this.remote, {
    bool Function(String)? isBookOpen,
  }) : isBookOpen = isBookOpen ?? ((_) => false);
  Set<String> get enabled => Set.unmodifiable(_enabled);
  Future<File> _file() async =>
      File('${(await library.storageDirectory()).path}/plex-progress.json');
  Future<void> init() => _loading ??= _load();
  Future<void> _load() async {
    final file = await _file();
    if (await file.exists()) {
      if (await file.length() > 4 * 1024 * 1024) {
        throw const FormatException('Sync state is too large.');
      }
      final data = jsonDecode(await file.readAsString()) as Map;
      _enabled.addAll((data['enabled'] as List).cast<String>());
      _records.addAll((data['records'] as Map).cast<String, dynamic>());
    }
  }

  Future<void> _save() async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'schema': 1,
        'enabled': _enabled.toList(),
        'records': _records,
      }),
      flush: true,
    );
    await temporary.rename(file.path);
  }

  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> setEnabled(String connectionId, bool enabled) =>
      _serial(() async {
        if (_disposed) throw StateError('Progress sync is shutting down');
        await init();
        await remote.init();
        final connection = remote.connections
            .where((c) => c.id == connectionId && c.kind == 'plex')
            .firstOrNull;
        if (connection == null) {
          throw const FormatException('Choose a Plex connection.');
        }
        if (enabled) {
          _enabled.add(connectionId);
        } else {
          _enabled.remove(connectionId);
        }
        await _save();
        if (!_disposed) notifyListeners();
      });
  void start() {
    _timer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      if (_automaticRunning || _disposed) return;
      _automaticRunning = true;
      synchronize().whenComplete(() => _automaticRunning = false).ignore();
    });
  }

  Future<Map<String, Object?>> synchronize({
    String? bookId,
    String? choice,
  }) => _serial(() async {
    if (_disposed) throw StateError('Progress sync is shutting down');
    await init();
    await remote.init();
    if (choice != null &&
        (!{'local', 'remote'}.contains(choice) || bookId == null)) {
      throw const FormatException('Resolve one book with local or remote.');
    }
    final links = await library.db.select(library.db.remoteLinks).get();
    for (final link in links) {
      if (bookId != null && link.bookId != bookId) continue;
      final connection = remote.connections
          .where(
            (c) =>
                _enabled.contains(c.id) &&
                c.kind == 'plex' &&
                c.url.toString() == link.serverUrl &&
                'plex:${c.username}' == link.userId,
          )
          .firstOrNull;
      if (connection == null) continue;
      try {
        if (isBookOpen(link.bookId)) {
          // Pushes are safe while playing, incoming seeks need an explicit
          // paused reload by the caller. Never silently move a playing book.
          if (choice == 'remote') {
            throw StateError(
              'Pause and unload this book before applying remote progress.',
            );
          }
        }
        issues.remove(link.bookId);
        await _sync(link, connection, choice: choice);
      } catch (error) {
        // SDK/HTTP errors are deliberately not echoed: they can include URLs.
        issues[link.bookId] = error is StateError
            ? error.message.toString()
            : 'Plex sync failed. Local progress is safe; retry when the server is available.';
      }
    }
    await _save();
    if (!_disposed) notifyListeners();
    return status();
  });
  Map<String, Object?> status() => {
    'enabled': _enabled.toList(),
    'conflicts': conflicts.toList(),
    'issues': Map.of(issues),
  };
  Future<Map<String, dynamic>> _request(RemoteConnection c, String path) async {
    final transport = RemoteClient(c);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client
          .getUrl(transport.uri(path))
          .timeout(const Duration(seconds: 10));
      req.followRedirects = false;
      req.headers.set('X-Plex-Token', c.secret);
      req.headers.set('Accept', 'application/json');
      req.headers.set(
        'X-Plex-Client-Identifier',
        'com.crispstrobe.crisperplayer',
      );
      final response = await req.close().timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw const HttpException('Plex request failed');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 10))) {
        bytes.addAll(chunk);
        if (bytes.length > 2 * 1024 * 1024) {
          throw const FormatException('Plex response too large');
        }
      }
      if (bytes.isEmpty || path.startsWith('./:/')) return {};
      return (jsonDecode(utf8.decode(bytes)) as Map).cast<String, dynamic>();
    } finally {
      client.close(force: true);
      transport.close();
    }
  }

  Future<List<Map<String, dynamic>>> _tracks(
    RemoteConnection c,
    String path,
  ) async {
    final data = await _request(c, path);
    final rows = ((data['MediaContainer'] as Map)['Metadata'] as List? ?? [])
        .map((r) => (r as Map).cast<String, dynamic>())
        .where((r) => r['type'] == 'track')
        .toList();
    rows.sort((a, b) {
      final disc = ((a['parentIndex'] as num?)?.toInt() ?? 1).compareTo(
        (b['parentIndex'] as num?)?.toInt() ?? 1,
      );
      return disc != 0
          ? disc
          : ((a['index'] as num?)?.toInt() ?? 0).compareTo(
              (b['index'] as num?)?.toInt() ?? 0,
            );
    });
    return rows;
  }

  static Map<String, int> _remotePosition(List<Map<String, dynamic>> rows) {
    var index = 0, offset = 0;
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final pos = (row['viewOffset'] as num?)?.toInt() ?? 0;
      final duration = (row['duration'] as num?)?.toInt() ?? 0;
      if (pos > 0) {
        index = i;
        offset = pos.clamp(0, duration);
        break;
      }
      if (((row['viewCount'] as num?)?.toInt() ?? 0) > 0) {
        index = i == rows.length - 1 ? i : i + 1;
        offset = i == rows.length - 1 ? duration : 0;
      } else {
        break;
      }
    }
    return {'index': index, 'offset': offset};
  }

  Future<void> _sync(
    RemoteLink link,
    RemoteConnection c, {
    String? choice,
  }) async {
    final book = await library.getBook(link.bookId);
    if (book == null) return;
    final tracks = await library.db.tracksFor(book.id);
    final rows = await _tracks(c, link.itemId);
    if (rows.isEmpty ||
        rows.length != tracks.length ||
        rows.any(
          (r) =>
              r['ratingKey'] == null ||
              (r['duration'] as num? ?? 0) <= 0 ||
              ((r['Media'] as List? ?? []).firstOrNull?['Part'] as List? ?? [])
                      .length !=
                  1,
        )) {
      throw StateError(
        'Server track layout cannot be matched safely. Re-download this book before syncing.',
      );
    }
    for (var i = 0; i < tracks.length; i++) {
      final known = tracks[i].durationMs;
      if (known != null &&
          (known - (rows[i]['duration'] as num).toInt()).abs() > 2000) {
        throw StateError(
          'Server durations no longer match the downloaded tracks. Re-download before syncing.',
        );
      }
    }
    final keys = rows.map((r) => r['ratingKey'].toString()).toList();
    final previous = _records[book.id] as Map?;
    if (previous != null && jsonEncode(previous['keys']) != jsonEncode(keys)) {
      throw StateError(
        'Plex tracks changed. Disable sync and re-import this book.',
      );
    }
    var index = tracks.indexWhere(
      (t) => t.filePath == book.lastPositionFilePath,
    );
    if (index < 0) index = 0;
    final local = {'index': index, 'offset': book.lastPositionMs};
    final incoming = _remotePosition(rows);
    final localCode = jsonEncode(local), remoteCode = jsonEncode(incoming);
    if (localCode == remoteCode) {
      _records[book.id] = {
        'keys': keys,
        'local': localCode,
        'remote': remoteCode,
      };
      conflicts.remove(book.id);
      return;
    }
    var localChanged = previous == null
        ? book.lastPlayedAtMs != null || index != 0 || book.lastPositionMs > 0
        : previous['local'] != localCode;
    var remoteChanged = previous == null
        ? incoming['index'] != 0 || incoming['offset'] != 0
        : previous['remote'] != remoteCode;
    if (choice == 'local') {
      localChanged = true;
      remoteChanged = false;
    }
    if (choice == 'remote') {
      localChanged = false;
      remoteChanged = true;
    }
    if (localChanged && remoteChanged) {
      conflicts.add(book.id);
      return;
    }
    if (remoteChanged) {
      if (isBookOpen(book.id)) {
        issues[book.id] =
            'Remote progress is ready. Close this book to apply it safely.';
        return;
      }
      final target = incoming['index']!;
      final pos = incoming['offset']!;
      final total = tracks.fold<int>(0, (n, t) => n + (t.durationMs ?? 0));
      final elapsed =
          tracks.take(target).fold<int>(0, (n, t) => n + (t.durationMs ?? 0)) +
          pos;
      // A network response must never overwrite progress changed while awaited.
      final current = await library.getBook(book.id);
      if (current == null ||
          current.lastPositionMs != book.lastPositionMs ||
          current.lastPositionFilePath != book.lastPositionFilePath) {
        conflicts.add(book.id);
        return;
      }
      await library.updateProgress(
        book.id,
        tracks[target].filePath,
        Duration(milliseconds: pos),
        Duration(milliseconds: elapsed),
        Duration(milliseconds: total),
        isPlaying: false,
      );
      _records[book.id] = {
        'keys': keys,
        'local': remoteCode,
        'remote': remoteCode,
      };
    } else if (localChanged) {
      for (var i = 0; i < rows.length; i++) {
        final key = keys[i];
        if (i < index) {
          await _request(
            c,
            './:/scrobble?${Uri(queryParameters: {'key': key, 'identifier': 'com.plexapp.plugins.library'}).query}',
          );
        } else {
          if (i > index || ((rows[i]['viewCount'] as num?)?.toInt() ?? 0) > 0) {
            await _request(
              c,
              './:/unscrobble?${Uri(queryParameters: {'key': key, 'identifier': 'com.plexapp.plugins.library'}).query}',
            );
          }
          await _request(
            c,
            './:/progress?${Uri(queryParameters: {'key': key, 'time': '${i == index ? book.lastPositionMs : 0}', 'identifier': 'com.plexapp.plugins.library'}).query}',
          );
        }
      }
      final confirmed = _remotePosition(await _tracks(c, link.itemId));
      // A server with music progress disabled must not silently acknowledge.
      if (jsonEncode(confirmed) != localCode) {
        throw StateError(
          'Plex did not retain this position. Enable Store track progress in the Plex library and retry.',
        );
      }
      _records[book.id] = {
        'keys': keys,
        'local': localCode,
        'remote': localCode,
      };
    }
    conflicts.remove(book.id);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }

  Future<void> shutdown() async {
    dispose();
    await _pending;
  }
}
