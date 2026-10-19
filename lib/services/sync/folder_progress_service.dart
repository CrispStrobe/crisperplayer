import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart' hide Hmac;
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../db/app_database.dart';
import '../library_service.dart';
import '../server/credential_store.dart';
import '../server/remote_library_service.dart';
import 'progress_record.dart';

Future<List<int>> _deriveProgressKey(Map<String, Object> values) async {
  final key =
      await Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: 210000,
        bits: 256,
      ).deriveKey(
        secretKey: SecretKey(utf8.encode(values['passphrase'] as String)),
        nonce: values['salt'] as List<int>,
      );
  return key.extractBytes();
}

/// Opt-in encrypted progress files in a user's own cloud folder. Each device
/// writes unique snapshots, retains its two newest and deletes only its own
/// older files after verifying the new upload. No accounts or hosted backend.
class FolderProgressService extends ChangeNotifier {
  final RemoteLibraryService remote;
  final LibraryService library;
  final ServerCredentialStore credentials;
  final bool Function(String) isBookOpen;
  final Map<String, ProgressRecord> _records = {};
  final Map<String, dynamic> _fingerprints = {};
  final Map<String, String> _bookKeys = {};
  final Map<String, List<ProgressRecord>> conflicts = {};
  final Map<String, String> issues = {};
  final _keys = <String, SecretKey>{};
  String? connectionId;
  String folder = '', _passphrase = '', _published = '';
  String _device = const Uuid().v4();
  int _generation = 0;
  List<int> _salt = List.generate(16, (_) => Random.secure().nextInt(256));
  bool _disposed = false;
  Future<void>? _loading;
  Future<void> _pending = Future.value();
  Timer? _timer;
  bool _automaticRunning = false;
  FolderProgressService(
    this.library,
    this.remote, {
    ServerCredentialStore? credentials,
    bool Function(String)? isBookOpen,
  }) : credentials =
           credentials ??
           KeychainCredentialStore(key: 'crisperplayer.progress.folder'),
       isBookOpen = isBookOpen ?? ((_) => false);
  bool get enabled => connectionId != null;
  Future<File> _file() async =>
      File('${(await library.storageDirectory()).path}/folder-progress.json');
  Future<void> init() => _loading ??= _load();
  Future<void> _load() async {
    final config = await credentials.read();
    if (config != null) {
      final data = jsonDecode(config) as Map;
      connectionId = data['connectionId'] as String?;
      folder = data['folder'] as String? ?? '';
      _passphrase = data['passphrase'] as String? ?? '';
    }
    final file = await _file();
    if (await file.exists()) {
      if (await file.length() > 16 * 1024 * 1024) {
        throw const FormatException('Progress journal too large');
      }
      final data = jsonDecode(await file.readAsString()) as Map;
      _device = data['device'] as String;
      if (!RegExp(r'^[a-f0-9-]{36}$').hasMatch(_device)) {
        throw const FormatException('Invalid device identity');
      }
      _generation = data['generation'] as int;
      if (data['salt'] != null) {
        _salt = base64Decode(data['salt'] as String);
        if (_salt.length != 16) {
          throw const FormatException('Invalid sync salt');
        }
      }
      _published = data['published'] as String;
      _fingerprints.addAll(
        (data['fingerprints'] as Map).cast<String, dynamic>(),
      );
      for (final e in (data['records'] as Map).entries) {
        _records[e.key as String] = ProgressRecord.fromJson(
          (e.value as Map).cast<String, dynamic>(),
        );
      }
    }
  }

  Future<void> _save() async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode({
        'device': _device,
        'salt': base64Encode(_salt),
        'generation': _generation,
        'published': _published,
        'fingerprints': _fingerprints,
        'records': {for (final e in _records.entries) e.key: e.value.toJson()},
      }),
      flush: true,
    );
    await temp.rename(file.path);
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _pending.then((_) async {
      if (_disposed) throw StateError('Progress sync is shutting down');
      return action();
    });
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> configure({
    String? connectionId,
    String folder = '',
    String passphrase = '',
  }) => _serial(() async {
    await init();
    await remote.init();
    if (connectionId != null) {
      if (passphrase.length < 12) {
        throw const FormatException(
          'Use the same sync passphrase of at least 12 characters on every device.',
        );
      }
      final connection = remote.connections
          .where(
            (c) =>
                c.id == connectionId &&
                {'webdav', 'nextcloud', 'filen', 'internxt'}.contains(c.kind),
          )
          .firstOrNull;
      if (connection == null) {
        throw const FormatException(
          'Select Nextcloud, WebDAV, Filen or Internxt.',
        );
      }
      final client = remote.createClient(connection);
      try {
        await client.browse(folder);
      } finally {
        client.close();
      }
    }
    await credentials.write(
      jsonEncode({
        'connectionId': connectionId,
        'folder': folder,
        'passphrase': passphrase,
      }),
    );
    if (this.connectionId != connectionId || this.folder != folder) {
      _published = '';
    }
    this.connectionId = connectionId;
    this.folder = folder;
    _passphrase = passphrase;
    _keys.clear();
    await _save();
    if (!_disposed) notifyListeners();
  });
  void start() {
    _timer ??= Timer.periodic(const Duration(minutes: 1), (_) {
      if (_automaticRunning || _disposed) return;
      _automaticRunning = true;
      synchronize().whenComplete(() => _automaticRunning = false).ignore();
    });
  }

  Future<String> _identity(Book book, List<BookTrack> tracks) async {
    final hashes = <String>[];
    for (final track in tracks) {
      final file = File(track.filePath);
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file) {
        throw const FormatException('Audio is unavailable');
      }
      final stamp = '${stat.size}:${stat.modified.microsecondsSinceEpoch}';
      final saved = _fingerprints[file.path] as Map?;
      String hash;
      if (saved?['stamp'] == stamp) {
        hash = saved!['hash'] as String;
      } else {
        hash = (await sha256.bind(file.openRead()).first).toString();
        if ((await file.stat()).modified != stat.modified ||
            await file.length() != stat.size) {
          throw const FormatException('Audio changed during fingerprinting');
        }
        _fingerprints[file.path] = {'stamp': stamp, 'hash': hash};
      }
      hashes.add(hash);
    }
    return sha256.convert(utf8.encode(jsonEncode(hashes))).toString();
  }

  Future<SecretKey> _key(List<int> salt) async {
    final id = base64Encode(salt);
    final existing = _keys[id];
    if (existing != null) return existing;
    final bytes = await compute(_deriveProgressKey, <String, Object>{
      'passphrase': _passphrase,
      'salt': salt,
    });
    if (_keys.length >= 128) _keys.remove(_keys.keys.first);
    return _keys[id] = SecretKey(bytes);
  }

  Future<List<int>> _encrypt(List<int> bytes) async {
    // A random per-device salt permits safe key reuse with fresh GCM nonces.
    final salt = _salt;
    final box = await AesGcm.with256bits().encrypt(
      bytes,
      secretKey: await _key(salt),
      aad: utf8.encode('crisperplayer-progress-v1'),
    );
    return utf8.encode(
      jsonEncode({
        'format': 'crisperplayer-progress-v1',
        'salt': base64Encode(salt),
        'nonce': base64Encode(box.nonce),
        'ciphertext': base64Encode(box.cipherText),
        'mac': base64Encode(box.mac.bytes),
      }),
    );
  }

  Future<Map<String, dynamic>> _decrypt(List<int> bytes) async {
    final envelope = jsonDecode(utf8.decode(bytes)) as Map;
    if (envelope['format'] != 'crisperplayer-progress-v1') {
      throw const FormatException('Unknown encrypted progress format');
    }
    final salt = base64Decode(envelope['salt'] as String),
        nonce = base64Decode(envelope['nonce'] as String),
        mac = base64Decode(envelope['mac'] as String);
    if (salt.length != 16 || nonce.length != 12 || mac.length != 16) {
      throw const FormatException('Invalid encryption envelope');
    }
    final plain = await AesGcm.with256bits().decrypt(
      SecretBox(
        base64Decode(envelope['ciphertext'] as String),
        nonce: nonce,
        mac: Mac(mac),
      ),
      secretKey: await _key(salt),
      aad: utf8.encode('crisperplayer-progress-v1'),
    );
    return (jsonDecode(utf8.decode(plain)) as Map).cast<String, dynamic>();
  }

  static String candidateId(ProgressRecord record) =>
      sha256.convert(utf8.encode(jsonEncode(record.toJson()))).toString();
  Future<Map<String, Object?>> synchronize({
    String? resolveBookId,
    String? choice,
  }) => _serial(() async {
    await init();
    if (!enabled) return status();
    await remote.init();
    final connection = remote.connections
        .where((c) => c.id == connectionId)
        .firstOrNull;
    if (connection == null) {
      issues['sync'] =
          'The sync connection was removed. Reconfigure progress sync.';
      return status();
    }
    final client = remote.createClient(connection);
    final stage = await Directory.systemTemp.createTemp('crisper-progress-');
    try {
      issues.clear();
      conflicts.clear();
      final books = await library.allBooks();
      final locals = <String, ({Book book, List<BookTrack> tracks})>{};
      for (final book in books) {
        final tracks = await library.db.tracksFor(book.id);
        if (tracks.isEmpty ||
            tracks.any((t) => t.durationMs == null || t.durationMs! <= 0)) {
          continue;
        }
        final key = await _identity(book, tracks);
        _bookKeys[book.id] = key;
        locals[key] = (book: book, tracks: tracks);
        var index = tracks.indexWhere(
          (t) => t.filePath == book.lastPositionFilePath,
        );
        if (index < 0) index = 0;
        final durations = tracks.map((t) => t.durationMs!).toList();
        final position = book.lastPositionMs.clamp(0, durations[index]);
        final old = _records[key];
        if (old == null) {
          // A fresh unplayed import must not compete with established progress.
          if (index != 0 || position != 0 || book.lastPlayedAtMs != null) {
            _records[key] = ProgressRecord(
              {_device: 1},
              index,
              position,
              durations,
            );
          }
        } else if (book.lastPlayedAtMs == null && index == 0 && position == 0) {
          if (!isBookOpen(book.id) && await _apply(book, tracks, old)) {
            locals[key] = (
              book: (await library.getBook(book.id))!,
              tracks: tracks,
            );
          }
        } else if (old.index != index || old.positionMs != position) {
          _records[key] = old.change(_device, index, position, durations);
        }
      }
      // Dirty progress and vector clocks survive even if every network call fails.
      await _save();
      final entries = await client.browse(folder);
      final pattern = RegExp(
        r'^crisper-state-([a-f0-9-]{36})-([0-9]+)[.]json$',
      );
      final snapshots =
          <String, List<({String path, String name, int generation})>>{};
      for (final entry in entries) {
        final match = pattern.firstMatch(entry.name);
        if (entry.type != 'file' || match == null) continue;
        snapshots.putIfAbsent(match[1]!, () => []).add((
          path: entry.path,
          name: entry.name,
          generation: int.parse(match[2]!),
        ));
      }
      if (snapshots.length > 100) {
        throw const FormatException('Too many sync devices');
      }
      for (final group in snapshots.values) {
        group.sort((a, b) => b.generation.compareTo(a.generation));
        final file = File(p.join(stage.path, 'incoming.json'));
        if (await file.exists()) await file.delete();
        await client.download(group.first.path, file, limit: 5 * 1024 * 1024);
        final incoming = await _decrypt(await file.readAsBytes());
        final match = pattern.firstMatch(group.first.name)!;
        if (incoming['device'] != match[1] ||
            incoming['generation'] != group.first.generation ||
            incoming['schema'] != 1) {
          throw const FormatException('Snapshot identity mismatch');
        }
        final rows = incoming['books'] as Map;
        if (rows.length > 10000) {
          throw const FormatException('Too many progress records');
        }
        for (final entry in rows.entries) {
          final key = entry.key as String;
          if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(key)) {
            throw const FormatException('Invalid book identity');
          }
          final record = ProgressRecord.fromJson(
            (entry.value as Map).cast<String, dynamic>(),
          );
          final local = _records[key];
          final book = locals[key];
          if (local != null && local.sameClock(record)) {
            if (!local.samePosition(record)) {
              throw const FormatException('Inconsistent progress clocks');
            }
            continue;
          }
          if (local != null && local.dominates(record)) continue;
          if (local != null &&
              !record.dominates(local) &&
              !local.samePosition(record)) {
            if (book != null) {
              conflicts.putIfAbsent(book.book.id, () => []).add(record);
            }
            continue;
          }
          if (book != null) {
            if (isBookOpen(book.book.id)) {
              issues[book.book.id] =
                  'Close this book to apply incoming progress.';
              continue;
            }
            if (!await _apply(book.book, book.tracks, record)) {
              conflicts.putIfAbsent(book.book.id, () => []).add(record);
              continue;
            }
          }
          if (book != null) {
            locals[key] = (
              book: (await library.getBook(book.book.id))!,
              tracks: book.tracks,
            );
          }
          _records[key] = local != null && !record.dominates(local)
              ? local.change(
                  _device,
                  record.index,
                  record.positionMs,
                  record.durations,
                  record,
                )
              : record;
        }
        await _save();
      }
      if (resolveBookId != null && choice != null) {
        final key = _bookKeys[resolveBookId],
            candidates = conflicts[resolveBookId] ?? [];
        final book = key == null ? null : locals[key];
        if (key == null || book == null || candidates.isEmpty) {
          throw const FormatException(
            'This conflict no longer exists. Sync and review again.',
          );
        }
        var selected = _records[key]!;
        if (choice != 'local') {
          selected = candidates.firstWhere(
            (r) => candidateId(r) == choice,
            orElse: () => throw const FormatException(
              'Remote position changed. Review the conflict again.',
            ),
          );
          if (isBookOpen(resolveBookId) ||
              !await _apply(book.book, book.tracks, selected)) {
            throw StateError('Close the book before applying remote progress.');
          }
        }
        var resolved = _records[key]!.change(
          _device,
          selected.index,
          selected.positionMs,
          selected.durations,
          selected,
        );
        for (final record in candidates) {
          resolved = resolved.change(
            _device,
            resolved.index,
            resolved.positionMs,
            resolved.durations,
            record,
          );
        }
        _records[key] = resolved;
        conflicts.remove(resolveBookId);
      }
      final rows = {for (final e in _records.entries) e.key: e.value.toJson()};
      final digest = sha256.convert(utf8.encode(jsonEncode(rows))).toString();
      if (digest != _published && rows.isNotEmpty) {
        _generation++;
        await _save();
        final name = 'crisper-state-$_device-$_generation.json';
        final bytes = await _encrypt(
          utf8.encode(
            jsonEncode({
              'schema': 1,
              'device': _device,
              'generation': _generation,
              'books': rows,
            }),
          ),
        );
        await client.putMetadata(folder, name, bytes);
        final created = (await client.browse(
          folder,
        )).where((e) => e.name == name).toList();
        if (created.length != 1) {
          throw const FormatException('Uploaded progress file is ambiguous');
        }
        final check = File(p.join(stage.path, 'verify.json'));
        await client.download(
          created.single.path,
          check,
          limit: 5 * 1024 * 1024,
        );
        final verified = await _decrypt(await check.readAsBytes());
        if (jsonEncode(verified['books']) != jsonEncode(rows)) {
          throw const FormatException('Progress upload verification failed');
        }
        _published = digest;
        await _save();
        // Keep the previous good snapshot as a fallback; never delete another
        // device's files or any filename outside this device's exact prefix.
        final older = snapshots[_device] ?? [];
        for (final entry in older.skip(1)) {
          await client.deleteMetadata(folder, entry.name);
        }
      }
      await _save();
    } catch (_) {
      issues['sync'] =
          'Could not sync progress. Check the connection and shared passphrase. Local progress is safe.';
    } finally {
      client.close();
      await stage.delete(recursive: true);
    }
    if (!_disposed) notifyListeners();
    return status();
  });
  Future<bool> _apply(
    Book book,
    List<BookTrack> tracks,
    ProgressRecord record,
  ) async {
    if (record.durations.length != tracks.length ||
        record.index >= tracks.length ||
        List.generate(
          tracks.length,
          (i) => (record.durations[i] - tracks[i].durationMs!).abs(),
        ).any((v) => v > 2000)) {
      return false;
    }
    final current = await library.getBook(book.id);
    if (current == null ||
        current.lastPositionMs != book.lastPositionMs ||
        current.lastPositionFilePath != book.lastPositionFilePath) {
      return false;
    }
    final position = record.positionMs.clamp(
      0,
      tracks[record.index].durationMs!,
    );
    final total = tracks.fold<int>(0, (n, t) => n + t.durationMs!);
    final elapsed =
        tracks.take(record.index).fold<int>(0, (n, t) => n + t.durationMs!) +
        position;
    await library.updateProgress(
      book.id,
      tracks[record.index].filePath,
      Duration(milliseconds: position),
      Duration(milliseconds: elapsed),
      Duration(milliseconds: total),
      isPlaying: false,
    );
    await (library.db.update(
      library.db.books,
    )..where((t) => t.id.equals(book.id))).write(
      BooksCompanion(
        lastPlayedAtMs: Value(DateTime.now().millisecondsSinceEpoch),
      ),
    );
    return true;
  }

  Map<String, Object?> status() => {
    'enabled': enabled,
    'connectionId': connectionId,
    'folder': folder,
    'issues': Map.of(issues),
    'conflicts': {
      for (final e in conflicts.entries)
        e.key: [
          for (final record in e.value)
            {
              'choice': candidateId(record),
              'index': record.index,
              'positionMs': record.positionMs,
            },
        ],
    },
  };
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _keys.clear();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> shutdown() async {
    dispose();
    await _pending;
    _keys.clear();
  }
}
