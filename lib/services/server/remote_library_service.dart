import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../library_service.dart';
import 'credential_store.dart';
import 'remote_client.dart';
import '../db/app_database.dart';

class RemoteLibraryService extends ChangeNotifier {
  final LibraryService library;
  final ServerCredentialStore credentials;
  final List<RemoteConnection> _connections = [];
  bool _loaded = false;
  bool busy = false;
  int downloadedBytes = 0;
  String? downloadName;
  Future<void>? _loading;
  RemoteLibraryService(this.library, {ServerCredentialStore? credentials})
    : credentials = credentials ?? KeychainCredentialStore();
  List<RemoteConnection> get connections => List.unmodifiable(_connections);
  Future<void> init() {
    if (_loaded) return Future.value();
    return _loading ??= _load().catchError((Object error) {
      _loading = null;
      throw error;
    });
  }

  Future<void> _load() async {
    final saved = await credentials.read();
    if (saved != null) {
      final rows = jsonDecode(saved) as List;
      _connections.addAll(
        rows
            .map(
              (r) =>
                  RemoteConnection.fromJson((r as Map).cast<String, dynamic>()),
            )
            .toList(),
      );
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> connect({
    required String name,
    required String kind,
    required String url,
    required String secret,
    String username = '',
    bool allowLocalHttp = false,
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
    );
    final client = RemoteClient(connection);
    try {
      await client.browse('');
    } finally {
      client.close();
    }
    final next = [..._connections, connection];
    await credentials.write(
      jsonEncode(next.map((c) => c.toJson(credentials: true)).toList()),
    );
    _connections.add(connection);
    notifyListeners();
  }

  Future<void> disconnect(String id) async {
    await init();
    if (busy) {
      throw const RemoteException('Wait for the current download to finish.');
    }
    final next = _connections.where((c) => c.id != id).toList();
    await credentials.write(
      jsonEncode(next.map((c) => c.toJson(credentials: true)).toList()),
    );
    _connections.removeWhere((c) => c.id == id);
    notifyListeners();
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

  Future<String> download(
    String connectionId,
    String path,
    String title, {
    String author = '',
    bool file = false,
  }) async {
    await init();
    if (busy) throw const RemoteException('Another download is in progress.');
    final connection = _connection(connectionId);
    final identity = '${connection.kind}:${connection.username}';
    final db = library.db;
    final existing =
        await (db.select(db.remoteLinks)..where(
              (t) =>
                  t.serverUrl.equals(connection.url.toString()) &
                  t.userId.equals(identity) &
                  t.itemId.equals(path),
            ))
            .getSingleOrNull();
    if (existing != null) return existing.bookId;
    busy = true;
    downloadedBytes = 0;
    downloadName = title;
    notifyListeners();
    final client = RemoteClient(connection);
    Directory? temporary;
    String? importedId;
    try {
      temporary = await Directory.systemTemp.createTemp('crisper_remote_');
      final entries = file
          ? [RemoteEntry(path, title, 'file')]
          : await client.tracks(path);
      if (entries.isEmpty) {
        throw const RemoteException(
          'No supported audio files were found here. Open the folder containing the book’s tracks.',
        );
      }
      final files = <String>[];
      var completed = 0;
      for (var i = 0; i < entries.length; i++) {
        final entry = entries[i];
        final name = p
            .basename(entry.name)
            .replaceAll(RegExp(r'[^\w. -]'), '_');
        final output = File(
          p.join(temporary.path, '${i.toString().padLeft(5, '0')}_$name'),
        );
        await client.download(
          entry.path,
          output,
          onBytes: (bytes) {
            downloadedBytes = completed + bytes;
            notifyListeners();
          },
        );
        completed += await output.length();
        files.add(output.path);
      }
      importedId = await library.importFiles(
        files,
        title: file ? p.basenameWithoutExtension(title) : title,
        author: author.isEmpty ? null : author,
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
              userId: identity,
              itemId: path,
            ),
          );
      return importedId;
    } catch (_) {
      if (importedId != null) await library.deleteBook(importedId);
      rethrow;
    } finally {
      client.close();
      if (temporary != null && await temporary.exists()) {
        await temporary.delete(recursive: true);
      }
      busy = false;
      downloadName = null;
      notifyListeners();
    }
  }

  Map<String, Object?> status() => {
    'connections': [for (final c in _connections) c.toJson()],
    'loaded': _loaded,
    'downloading': busy,
    'downloadName': downloadName,
    'downloadedBytes': downloadedBytes,
  };
}
