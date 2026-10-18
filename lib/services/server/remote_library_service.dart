import 'package:crisp_storage/crisp_storage.dart'
    show
        StoredList,
        TransferOperation,
        TransferScheduler,
        ScheduledTransfer,
        TransferCancelled;
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../library_service.dart';
import 'credential_store.dart';
import 'remote_client.dart';
import '../db/app_database.dart';

class RemoteDownload {
  final String id, connectionId, path, title, author;
  final bool file;
  String phase = 'paused';
  String? error;
  int bytes = 0;
  RemoteDownload({
    required this.id,
    required this.connectionId,
    required this.path,
    required this.title,
    this.author = '',
    this.file = false,
  });
  Map<String, Object?> toJson() => {
    'id': id,
    'connectionId': connectionId,
    'path': path,
    'title': title,
    'author': author,
    'file': file,
    'phase': phase,
    'error': error,
    'bytes': bytes,
  };
  factory RemoteDownload.fromJson(Map<String, dynamic> row) => RemoteDownload(
    id: row['id'] as String,
    connectionId: row['connectionId'] as String,
    path: row['path'] as String,
    title: row['title'] as String,
    author: row['author'] as String? ?? '',
    file: row['file'] == true,
  );
}

class _DownloadOperation implements TransferOperation {
  final _cancelled = Completer<void>();
  @override
  bool get isCancelled => _cancelled.isCompleted;
  @override
  Future<void> get cancellationFuture => _cancelled.future;
  @override
  bool get isPaused => false;
  @override
  Future<void>? get pauseFuture => null;
  @override
  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }
}

class RemoteLibraryService extends ChangeNotifier {
  final LibraryService library;
  final ServerCredentialStore credentials;
  final List<RemoteConnection> _connections = [];
  final Map<String, RemoteDownload> _downloads = {};
  bool _loaded = false, _disposed = false, _pausing = false;
  late final _queue = TransferScheduler<_DownloadOperation>(
    maxConcurrent: 1,
    maxRetries: 2,
    onChanged: _changed,
  );
  final _scheduled = <String, _DownloadOperation>{};
  final _preparing = <String>{};
  bool get busy => _queue.hasActive || _queue.pendingCount > 0;
  int get downloadedBytes => _active?.bytes ?? 0;
  RemoteDownload? get _current =>
      _active ??
      (_queue.activeTasks.isEmpty
          ? null
          : _downloads[_queue.activeTasks.first.id]);
  String? get downloadName => _current?.title;
  bool get canPause => ['downloading', 'retrying'].contains(_current?.phase);
  RemoteDownload? _active;
  RemoteClient? _activeClient;
  Future<void>? _loading;
  late final StoredList<RemoteConnection> _profiles = StoredList(
    read: credentials.read,
    write: credentials.write,
    decode: RemoteConnection.fromJson,
    encode: (c) => c.toJson(credentials: true),
  );
  RemoteLibraryService(this.library, {ServerCredentialStore? credentials})
    : credentials = credentials ?? KeychainCredentialStore();
  List<RemoteConnection> get connections => List.unmodifiable(_connections);
  List<RemoteDownload> get downloads => List.unmodifiable(_downloads.values);
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<Directory> _root() async =>
      Directory(p.join((await library.storageDirectory()).path, 'downloads'));
  Future<Directory> _directory(String id) async {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(id)) {
      throw const FormatException('Invalid download ID');
    }
    return Directory(p.join((await _root()).path, id));
  }

  Future<void> init() {
    if (_loaded) return Future.value();
    return _loading ??= _load().catchError((Object error) {
      _loading = null;
      throw error;
    });
  }

  Future<void> _load() async {
    final connections = await _profiles.getAll();
    final root = await _root();
    final jobs = <RemoteDownload>[];
    if (await root.exists()) {
      await for (final entry in root.list(followLinks: false)) {
        if (entry is! Directory ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(p.basename(entry.path))) {
          continue;
        }
        try {
          final manifest = File(p.join(entry.path, 'job.json'));
          if (await manifest.length() > 64 * 1024) continue;
          final job = RemoteDownload.fromJson(
            (jsonDecode(await manifest.readAsString()) as Map)
                .cast<String, dynamic>(),
          );
          if (job.id != p.basename(entry.path)) continue;
          await for (final part in entry.list(followLinks: false)) {
            if (part is File && RemoteClient.isAudio(part.path)) {
              job.bytes += await part.length();
            }
          }
          jobs.add(job);
        } on IOException {
          /* A damaged disposable transfer cannot affect the library. */
        } on FormatException {
          /* Skip invalid manifests. */
        } on TypeError {
          /* Skip invalid manifests. */
        }
      }
    }
    _connections
      ..clear()
      ..addAll(connections);
    _downloads.addEntries(jobs.map((j) => MapEntry(j.id, j)));
    _loaded = true;
    _changed();
  }

  Future<void> connect({
    required String name,
    required String kind,
    required String url,
    required String secret,
    String username = '',
    bool allowLocalHttp = false,
    String? hostKey,
  }) async {
    await init();
    final connection = RemoteConnection(
      id: const Uuid().v4(),
      name: name.trim(),
      kind: kind,
      url: url,
      secret: secret,
      username: username,
      allowLocalHttp: allowLocalHttp,
      hostKey: hostKey,
    );
    final client = RemoteClient(connection);
    try {
      await client.browse('');
    } finally {
      client.close();
    }
    await _saveConnections((current) => [...current, connection]);
  }

  Future<void> _saveConnections(
    List<RemoteConnection> Function(List<RemoteConnection>) build,
  ) {
    return _profiles.update(build).then((next) {
      _connections
        ..clear()
        ..addAll(next);
      _changed();
    });
  }

  Future<void> disconnect(String id) async {
    await init();
    await _saveConnections((current) {
      if (busy) {
        throw const RemoteException('Wait for the current download to finish.');
      }
      return current.where((c) => c.id != id).toList();
    });
  }

  RemoteConnection _connection(String id) => _connections.firstWhere(
    (c) => c.id == id,
    orElse: () => throw const RemoteException('Connection was not found.'),
  );
  Future<List<RemoteEntry>> browse(String id, String path) async {
    await init();
    final client = RemoteClient(_connection(id));
    try {
      return await client.browse(path);
    } finally {
      client.close();
    }
  }

  Future<RemoteDownload> _prepare(
    String connectionId,
    String path,
    String title, {
    String author = '',
    bool file = false,
  }) async {
    await init();
    final validation = RemoteClient(_connection(connectionId));
    try {
      validation.uri(path);
    } finally {
      validation.close();
    }
    final id = sha256
        .convert(utf8.encode(jsonEncode([connectionId, path, file])))
        .toString();
    final job =
        _downloads[id] ??
        RemoteDownload(
          id: id,
          connectionId: connectionId,
          path: path,
          title: title,
          author: author,
          file: file,
        );
    if (_scheduled.containsKey(id) || !_preparing.add(id)) {
      throw const RemoteException('This download is already queued.');
    }
    try {
      final directory = await _directory(id);
      await directory.create(recursive: true);
      final temporary = File(p.join(directory.path, 'job.tmp'));
      await temporary.writeAsString(jsonEncode(job.toJson()), flush: true);
      await temporary.rename(p.join(directory.path, 'job.json'));
      _downloads[id] = job;
      return job;
    } finally {
      _preparing.remove(id);
    }
  }

  Future<String> download(
    String connectionId,
    String path,
    String title, {
    String author = '',
    bool file = false,
  }) async => _schedule(
    await _prepare(connectionId, path, title, author: author, file: file),
  );
  Future<RemoteDownload> startDownload(
    String connectionId,
    String path,
    String title, {
    String author = '',
    bool file = false,
  }) async {
    final job = await _prepare(
      connectionId,
      path,
      title,
      author: author,
      file: file,
    );
    unawaited(
      _schedule(job).then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
    return job;
  }

  Future<String> resume(String id) async {
    await init();
    final job = _downloads[id];
    if (job == null) throw const RemoteException('Download was not found.');
    return _schedule(job);
  }

  Future<void> queueResume(String id) async {
    await init();
    final job = _downloads[id];
    if (job == null) throw const RemoteException('Download was not found.');
    unawaited(
      _schedule(job).then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }

  Future<void> discard(String id) async {
    await init();
    if (_active?.id == id) {
      throw const RemoteException('Pause the download before discarding it.');
    }
    _queue.cancel(id);
    final directory = await _directory(id);
    if (await directory.exists()) await directory.delete(recursive: true);
    _downloads.remove(id);
    _changed();
  }

  void pauseDownload() {
    if (!busy) return;
    if (!canPause) {
      throw const RemoteException(
        'Finishing the library import. Wait for it to complete.',
      );
    }
    _pausing = true;
    if (_current != null) _scheduled[_current!.id]?.cancel();
    _activeClient?.close();
  }

  void _checkPaused() {
    if (_pausing || _disposed) {
      throw const RemoteException(
        'Download paused. Resume it from Servers & NAS.',
      );
    }
  }

  Future<String> _schedule(RemoteDownload job) {
    if (_scheduled.containsKey(job.id)) {
      throw const RemoteException('This download is already queued.');
    }
    final operation = _DownloadOperation();
    final result = Completer<String>();
    _scheduled[job.id] = operation;
    job.phase = 'queued';
    job.error = null;
    _queue.enqueue(
      ScheduledTransfer(
        id: job.id,
        operation: operation,
        execute: () async {
          try {
            final id = await _perform(job);
            if (!result.isCompleted) result.complete(id);
          } catch (error) {
            if (error is RemoteException &&
                error.retryable &&
                !operation.isCancelled) {
              job.phase = 'retrying';
              _changed();
            }
            rethrow;
          }
        },
        onDone: (error) {
          _scheduled.remove(job.id);
          if (error != null) {
            if (error is TransferCancelled) {
              job.phase = 'paused';
              job.error = null;
            } else {
              job.phase = 'failed';
              job.error = '$error';
            }
            if (!result.isCompleted) {
              result.completeError(
                error is TransferCancelled
                    ? const RemoteException('Download paused.')
                    : error,
              );
            }
          }
          _changed();
        },
      ),
    );
    return result.future;
  }

  Future<String> _perform(RemoteDownload job) async {
    if (_active != null) {
      throw const RemoteException('Another download is in progress.');
    }
    final connection = _connection(job.connectionId);
    _pausing = false;
    _active = job;
    job.phase = 'downloading';
    job.error = null;
    job.bytes = 0;
    final client = _activeClient = RemoteClient(connection);
    _changed();
    final db = library.db;
    String? importedId;
    try {
      final existing =
          await (db.select(db.remoteLinks)..where(
                (t) =>
                    t.serverUrl.equals(connection.url.toString()) &
                    t.userId.equals(
                      '${connection.kind}:${connection.username}',
                    ) &
                    t.itemId.equals(job.path),
              ))
              .getSingleOrNull();
      if (existing != null) {
        await _complete(job);
        return existing.bookId;
      }
      final directory = await _directory(job.id);
      final entries = job.file
          ? [
              RemoteEntry(
                job.path,
                RemoteClient.isAudio(job.title)
                    ? job.title
                    : Uri.parse(job.path).pathSegments.last,
                'file',
              ),
            ]
          : await client.tracks(job.path);
      _checkPaused();
      if (entries.isEmpty) {
        throw const RemoteException(
          'No supported audio files were found here. Open the folder containing the book’s tracks.',
        );
      }
      final files = <String>[];
      var completed = 0;
      for (var i = 0; i < entries.length; i++) {
        _checkPaused();
        final entry = entries[i];
        final name = p
            .basename(entry.name)
            .replaceAll(RegExp(r'[^\w. -]'), '_');
        // Keep the audio extension for native probing.
        final output = File(
          p.join(directory.path, '${i.toString().padLeft(5, '0')}_$name'),
        );
        await client.download(
          entry.path,
          output,
          onBytes: (bytes) {
            _checkPaused();
            job.bytes = completed + bytes;
            _changed();
          },
        );
        completed += await output.length();
        files.add(output.path);
      }
      _checkPaused();
      job.phase = 'importing';
      _changed();
      importedId = await library.importFiles(
        files,
        title: job.file ? p.basenameWithoutExtension(job.title) : job.title,
        author: job.author.isEmpty ? null : job.author,
      );
      if (importedId == null) {
        throw const RemoteException('No book was imported.');
      }
      await db
          .into(db.remoteLinks)
          .insert(
            RemoteLinksCompanion.insert(
              bookId: importedId,
              serverUrl: connection.url.toString(),
              userId: '${connection.kind}:${connection.username}',
              itemId: job.path,
            ),
          );
      await _complete(job);
      return importedId;
    } catch (error) {
      if (importedId != null) await library.deleteBook(importedId);
      job.phase = _pausing || _disposed ? 'paused' : 'failed';
      job.error = job.phase == 'paused' ? null : '$error';
      if (_pausing) throw const RemoteException('Download paused.');
      rethrow;
    } finally {
      client.close();
      _activeClient = null;
      _active = null;
      _changed();
    }
  }

  Future<void> _complete(RemoteDownload job) async {
    final directory = await _directory(job.id);
    // A successfully imported book must survive disposable-cache cleanup errors.
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } on IOException {
      /* Retry cleanup on next import. */
    }
    _downloads.remove(job.id);
  }

  Map<String, Object?> status() => {
    'connections': [for (final c in _connections) c.toJson()],
    'loaded': _loaded,
    'downloading': busy,
    'downloadName': downloadName,
    'downloadedBytes': downloadedBytes,
    'canPause': canPause,
    'queuedDownloads': _queue.pendingCount,
    'downloads': [for (final job in downloads) job.toJson()],
  };
  @override
  void dispose() {
    _disposed = true;
    _queue.dispose();
    _pausing = true;
    _activeClient?.close();
    super.dispose();
  }
}
