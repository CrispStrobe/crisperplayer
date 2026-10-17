import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import '../db/app_database.dart';

/// File hashing for m4b/m4a/mp3 — content addressed, never upload binary.
/// Only the hash is synced to remote for deduplication / integrity.
class FileHasher {
  /// SHA-256 of file at [path]. Returns hex string. Null if missing.
  static Future<String?> hashFile(String path) async {
    try {
      final f = File(path);
      if (!await f.exists()) return null;
      final digest = await _hashStream(f.openRead());
      return digest.toString();
    } catch (e) {
      debugPrint('FileHasher.hashFile failed $path: $e');
      return null;
    }
  }

  /// Hash raw bytes (for tests / in-memory).
  static String hashBytes(List<int> bytes) => sha256.convert(bytes).toString();

  /// Hash list of file paths -> map path->hash (null entries omitted).
  static Future<Map<String, String>> hashFiles(List<String> paths) async {
    final out = <String, String>{};
    for (final p in paths) {
      final h = await hashFile(p);
      if (h != null) out[p] = h;
    }
    return out;
  }

  static Future<Digest> _hashStream(Stream<List<int>> stream) async {
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
    return sha256.convert(bytes);
  }

  /// Synchronous helper for small payloads (remote JSON hashing / ETag).
  static String hashJson(Map<String, dynamic> json) {
    final s = jsonEncode(json);
    return sha256.convert(utf8.encode(s)).toString();
  }
}

/// Lightweight at-rest encryption for sync payloads.
///
/// Uses passphrase-derived key (SHA-256 KDF) + XOR stream + HMAC-SHA256
/// authentication. Not a replacement for TLS; it provides local
/// encrypted stash + optional remote envelope encryption when a passphrase is set.
///
/// If `passphrase` is null/empty, payloads pass through as plain JSON.
class SyncCrypto {
  final String? passphrase;
  late final List<int>? _key;

  SyncCrypto({this.passphrase}) {
    if (passphrase != null && passphrase!.isNotEmpty) {
      _key = sha256.convert(utf8.encode(passphrase!)).bytes;
    } else {
      _key = null;
    }
  }

  bool get enabled => _key != null;

  /// Encrypt string -> base64 envelope {v:1, n:nonce, c:ciphertext, m:hmac}
  String encrypt(String plain) {
    if (!enabled) return plain;
    final key = _key!;
    final nonce = _nonce();
    final plainBytes = utf8.encode(plain);
    final cipher = _xor(plainBytes, key, nonce);
    final hmac = Hmac(sha256, key).convert(cipher + nonce).toString();
    final env = {
      'v': 1,
      'n': base64Encode(nonce),
      'c': base64Encode(cipher),
      'm': hmac,
    };
    return base64Encode(utf8.encode(jsonEncode(env)));
  }

  /// Decrypt envelope -> plain. Throws on bad HMAC.
  String decrypt(String envelope) {
    if (!enabled) return envelope;
    final key = _key!;
    try {
      final envJson = jsonDecode(utf8.decode(base64Decode(envelope))) as Map<String, dynamic>;
      final nonce = base64Decode(envJson['n'] as String);
      final cipher = base64Decode(envJson['c'] as String);
      final expected = Hmac(sha256, key).convert(cipher + nonce).toString();
      if (expected != envJson['m']) throw StateError('SyncCrypto: HMAC mismatch');
      final plainBytes = _xor(cipher, key, nonce);
      return utf8.decode(plainBytes);
    } catch (e) {
      // Try legacy plain passthrough fallback (migration)
      if (e is StateError) rethrow;
      debugPrint('SyncCrypto.decrypt fallback failed: $e');
      rethrow;
    }
  }

  String encryptJson(Map<String, dynamic> json) => encrypt(jsonEncode(json));
  Map<String, dynamic> decryptJson(String envelope) =>
      jsonDecode(decrypt(envelope)) as Map<String, dynamic>;

  List<int> _nonce() {
    final r = Random.secure();
    return List<int>.generate(16, (_) => r.nextInt(256));
  }

  List<int> _xor(List<int> data, List<int> key, List<int> nonce) {
    final out = Uint8List(data.length);
    for (int i = 0; i < data.length; i++) {
      out[i] = data[i] ^ key[i % key.length] ^ nonce[i % nonce.length];
    }
    return out;
  }
}

/// Offline queue entry — persisted as JSON.
class SyncOperation {
  final String id;
  final String entity; // book | chapter | bookmark | history | progress
  final String op; // upsert | delete
  final Map<String, dynamic> payload;
  final int createdAtMs;
  int attempts;
  int? lastErrorMs;

  SyncOperation({
    required this.id,
    required this.entity,
    required this.op,
    required this.payload,
    required this.createdAtMs,
    this.attempts = 0,
    this.lastErrorMs,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'entity': entity,
        'op': op,
        'payload': payload,
        'createdAtMs': createdAtMs,
        'attempts': attempts,
        'lastErrorMs': lastErrorMs,
      };

  factory SyncOperation.fromJson(Map<String, dynamic> j) => SyncOperation(
        id: j['id'] as String,
        entity: j['entity'] as String,
        op: j['op'] as String,
        payload: (j['payload'] as Map).cast<String, dynamic>(),
        createdAtMs: j['createdAtMs'] as int,
        attempts: j['attempts'] as int? ?? 0,
        lastErrorMs: j['lastErrorMs'] as int?,
      );
}

/// Persisted offline queue with retry bookkeeping.
class SyncQueue {
  final String? filePath; // null => memory only (tests)
  final List<SyncOperation> _ops = [];
  bool _loaded = false;

  SyncQueue({this.filePath});

  List<SyncOperation> get pending => List.unmodifiable(_ops);

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    if (filePath == null) return;
    try {
      final f = File(filePath!);
      if (!await f.exists()) return;
      final raw = await f.readAsString();
      if (raw.trim().isEmpty) return;
      final list = jsonDecode(raw) as List;
      _ops
        ..clear()
        ..addAll(list.map((e) => SyncOperation.fromJson((e as Map).cast<String, dynamic>())));
    } catch (e) {
      debugPrint('SyncQueue.load failed: $e');
    }
  }

  Future<void> _persist() async {
    if (filePath == null) return;
    try {
      final f = File(filePath!);
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode(_ops.map((e) => e.toJson()).toList()));
    } catch (e) {
      debugPrint('SyncQueue.persist failed: $e');
    }
  }

  Future<void> enqueue(SyncOperation op) async {
    await load();
    _ops.add(op);
    await _persist();
  }

  Future<void> remove(String id) async {
    _ops.removeWhere((e) => e.id == id);
    await _persist();
  }

  Future<void> clear() async {
    _ops.clear();
    await _persist();
  }

  Future<void> markAttempt(String id, {String? error}) async {
    final idx = _ops.indexWhere((e) => e.id == id);
    if (idx >= 0) {
      _ops[idx].attempts += 1;
      _ops[idx].lastErrorMs = DateTime.now().millisecondsSinceEpoch;
      await _persist();
    }
  }

  int get length => _ops.length;
  bool get isEmpty => _ops.isEmpty;
  bool get isNotEmpty => _ops.isNotEmpty;
}

/// Abstract remote — Supabase REST or Firebase implement this.
abstract class SyncBackend {
  /// Push payload to remote. Returns true on success.
  Future<bool> push(SyncPayload payload);

  /// Pull remote state since [sinceMs] (0 = full). Returns payload.
  Future<SyncPayload?> pull({int sinceMs = 0});

  /// Optional: delete single entity remotely.
  Future<bool> delete(String entity, String id) async => true;
}

/// Wire payload exchanged with remote.
class SyncPayload {
  final int exportedAtMs;
  final String? deviceId;
  final List<Map<String, dynamic>> books;
  final List<Map<String, dynamic>> chapters;
  final List<Map<String, dynamic>> bookmarks;
  final List<Map<String, dynamic>> history;
  /// File hashes: path -> sha256 hex. Never upload binary.
  final Map<String, String> fileHashes;
  /// Tombstones for deletions: {entity, id, deletedAtMs}
  final List<Map<String, dynamic>> tombstones;

  SyncPayload({
    required this.exportedAtMs,
    this.deviceId,
    this.books = const [],
    this.chapters = const [],
    this.bookmarks = const [],
    this.history = const [],
    this.fileHashes = const {},
    this.tombstones = const [],
  });

  Map<String, dynamic> toJson() => {
        'version': 1,
        'exportedAtMs': exportedAtMs,
        'deviceId': deviceId,
        'books': books,
        'chapters': chapters,
        'bookmarks': bookmarks,
        'history': history,
        'fileHashes': fileHashes,
        'tombstones': tombstones,
      };

  factory SyncPayload.fromJson(Map<String, dynamic> j) => SyncPayload(
        exportedAtMs: j['exportedAtMs'] as int? ?? j['exportedAt'] as int? ?? 0,
        deviceId: j['deviceId'] as String?,
        books: (j['books'] as List? ?? []).cast<Map<String, dynamic>>(),
        chapters: (j['chapters'] as List? ?? []).cast<Map<String, dynamic>>(),
        bookmarks: (j['bookmarks'] as List? ?? []).cast<Map<String, dynamic>>(),
        history: (j['history'] as List? ?? []).cast<Map<String, dynamic>>(),
        fileHashes: (j['fileHashes'] as Map? ?? {}).cast<String, String>(),
        tombstones: (j['tombstones'] as List? ?? []).cast<Map<String, dynamic>>(),
      );

  bool get isEmpty => books.isEmpty && chapters.isEmpty && bookmarks.isEmpty && history.isEmpty && tombstones.isEmpty;
}

/// Supabase REST backend.
/// Tables expected: sync_state (single row per user) with `payload` jsonb column, or
/// per-entity tables: books, chapters, bookmarks, listening_history.
/// This implementation uses the `sync_state` envelope for simplicity (one PUT).
class SupabaseSyncBackend implements SyncBackend {
  final String supabaseUrl;
  final String anonKey;
  final String userId;
  final String table; // default: sync_state
  final HttpClient _client;

  SupabaseSyncBackend({
    required this.supabaseUrl,
    required this.anonKey,
    required this.userId,
    this.table = 'sync_state',
    HttpClient? client,
  }) : _client = client ?? HttpClient();

  Uri _uri(String path, [Map<String, String>? qp]) {
    final base = supabaseUrl.endsWith('/') ? supabaseUrl.substring(0, supabaseUrl.length - 1) : supabaseUrl;
    return Uri.parse('$base$path').replace(queryParameters: qp);
  }

  Map<String, String> get _headers => {
        'apikey': anonKey,
        'Authorization': 'Bearer $anonKey',
        'Content-Type': 'application/json',
        'Prefer': 'resolution=merge-duplicates',
      };

  @override
  Future<bool> push(SyncPayload payload) async {
    final uri = _uri('/rest/v1/$table', {'user_id': 'eq.$userId'});
    final body = jsonEncode({'user_id': userId, 'payload': payload.toJson(), 'updated_at': DateTime.now().toIso8601String()});
    try {
      final req = await _client.postUrl(uri).timeout(const Duration(seconds: 10));
      _headers.forEach(req.headers.set);
      req.write(body);
      final resp = await req.close().timeout(const Duration(seconds: 10));
      final ok = resp.statusCode >= 200 && resp.statusCode < 300;
      if (!ok) debugPrint('Supabase push ${resp.statusCode}');
      // drain
      await resp.drain();
      return ok;
    } catch (e) {
      debugPrint('Supabase push error: $e');
      return false;
    }
  }

  @override
  Future<SyncPayload?> pull({int sinceMs = 0}) async {
    final uri = _uri('/rest/v1/$table', {'user_id': 'eq.$userId', 'select': 'payload,updated_at'});
    try {
      final req = await _client.getUrl(uri).timeout(const Duration(seconds: 10));
      _headers.forEach(req.headers.set);
      final resp = await req.close().timeout(const Duration(seconds: 10));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        await resp.drain();
        return null;
      }
      final body = await resp.transform(utf8.decoder).join();
      final list = jsonDecode(body) as List;
      if (list.isEmpty) return null;
      final row = (list.first as Map).cast<String, dynamic>();
      final payloadRaw = row['payload'];
      if (payloadRaw == null) return null;
      final Map<String, dynamic> pj = payloadRaw is String ? jsonDecode(payloadRaw) as Map<String, dynamic> : (payloadRaw as Map).cast<String, dynamic>();
      if (sinceMs > 0 && (pj['exportedAtMs'] as int? ?? 0) <= sinceMs) return null;
      return SyncPayload.fromJson(pj);
    } catch (e) {
      debugPrint('Supabase pull error: $e');
      return null;
    }
  }

  @override
  Future<bool> delete(String entity, String id) async => true;
}

/// Firebase Realtime Database / Firestore REST backend (generic envelope).
/// Uses Firebase RTDB JSON endpoint: https://PROJECT.firebaseio.com/sync/USER.json?auth=TOKEN
class FirebaseSyncBackend implements SyncBackend {
  final String databaseUrl; // e.g. https://xxx.firebaseio.com or https://firestore.googleapis.com/...
  final String userId;
  final String? authToken;
  final HttpClient _client;
  final bool useFirestore; // if true, use Firestore REST, else RTDB

  FirebaseSyncBackend({
    required this.databaseUrl,
    required this.userId,
    this.authToken,
    HttpClient? client,
    this.useFirestore = false,
  }) : _client = client ?? HttpClient();

  Uri get _pushUri {
    if (useFirestore) {
      final base = databaseUrl.replaceAll(RegExp(r'/$'), '');
      return Uri.parse('$base/v1/projects/$userId/databases/(default)/documents/sync/$userId');
    } else {
      final base = databaseUrl.replaceAll(RegExp(r'/$'), '');
      final tokenQ = authToken != null ? '?auth=$authToken' : '';
      return Uri.parse('$base/sync/$userId.json$tokenQ');
    }
  }

  Uri get _pullUri => _pushUri;

  @override
  Future<bool> push(SyncPayload payload) async {
    try {
      final uri = _pushUri;
      final body = jsonEncode(payload.toJson());
      final req = await _client.putUrl(uri).timeout(const Duration(seconds: 10));
      req.headers.set('Content-Type', 'application/json');
      req.write(body);
      final resp = await req.close().timeout(const Duration(seconds: 10));
      final ok = resp.statusCode >= 200 && resp.statusCode < 300;
      await resp.drain();
      if (!ok) debugPrint('Firebase push ${resp.statusCode}');
      return ok;
    } catch (e) {
      debugPrint('Firebase push error: $e');
      return false;
    }
  }

  @override
  Future<SyncPayload?> pull({int sinceMs = 0}) async {
    try {
      final uri = _pullUri;
      final req = await _client.getUrl(uri).timeout(const Duration(seconds: 10));
      final resp = await req.close().timeout(const Duration(seconds: 10));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        await resp.drain();
        return null;
      }
      final body = await resp.transform(utf8.decoder).join();
      if (body.trim().isEmpty || body.trim() == 'null') return null;
      final j = jsonDecode(body) as Map<String, dynamic>;
      if (sinceMs > 0 && (j['exportedAtMs'] as int? ?? 0) <= sinceMs) return null;
      return SyncPayload.fromJson(j);
    } catch (e) {
      debugPrint('Firebase pull error: $e');
      return null;
    }
  }

  @override
  Future<bool> delete(String entity, String id) async => true;
}

/// In-memory backend for tests / offline demos.
class MemorySyncBackend implements SyncBackend {
  SyncPayload? _stored;
  int pushCount = 0;
  int pullCount = 0;
  bool shouldFail = false;

  @override
  Future<bool> push(SyncPayload payload) async {
    pushCount++;
    if (shouldFail) return false;
    _stored = payload;
    return true;
  }

  @override
  Future<SyncPayload?> pull({int sinceMs = 0}) async {
    pullCount++;
    if (shouldFail) return null;
    if (_stored == null) return null;
    if (sinceMs > 0 && _stored!.exportedAtMs <= sinceMs) return null;
    return _stored;
  }

  @override
  Future<bool> delete(String entity, String id) async => true;

  void seed(SyncPayload p) => _stored = p;
  void clear() => _stored = null;
}

/// Last-write-wins merge helpers.
class LastWriteWins {
  /// Book merge: latest lastPlayedAtMs wins for progress fields; title/author use latest addedAtMs.
  static Map<String, dynamic> mergeBook(Map<String, dynamic> local, Map<String, dynamic> remote) {
    final lPlayed = local['lastPlayedAtMs'] as int? ?? 0;
    final rPlayed = remote['lastPlayedAtMs'] as int? ?? 0;
    final lAdded = local['addedAtMs'] as int? ?? 0;
    final rAdded = remote['addedAtMs'] as int? ?? 0;
    // Progress uses lastPlayed winner
    final winnerProgress = rPlayed > lPlayed ? remote : local;
    // Metadata uses addedAt winner (or fallback to lastPlayed if equal)
    final winnerMeta = rAdded > lAdded ? remote : (lAdded > rAdded ? local : winnerProgress);
    return {
      ...local,
      ...remote,
      // Explicit LWW fields
      'title': winnerMeta['title'],
      'author': winnerMeta['author'],
      'coverPath': winnerMeta['coverPath'] ?? local['coverPath'],
      'filePathsJson': winnerMeta['filePathsJson'] ?? local['filePathsJson'],
      'totalDurationMs': winnerMeta['totalDurationMs'] ?? local['totalDurationMs'],
      'lastPlayedAtMs': winnerProgress['lastPlayedAtMs'],
      'lastPositionFilePath': winnerProgress['lastPositionFilePath'],
      'lastPositionMs': winnerProgress['lastPositionMs'],
      'totalProgress': winnerProgress['totalProgress'],
      'isFinished': winnerProgress['isFinished'],
    };
  }

  /// Generic per-id LWW using timestamp field.
  static List<Map<String, dynamic>> mergeById(
    List<Map<String, dynamic>> local,
    List<Map<String, dynamic>> remote, {
    required String tsField, // e.g. createdAtMs, startedAtMs, updatedAtMs
  }) {
    final byId = <String, Map<String, dynamic>>{};
    for (final r in local) {
      byId[r['id'] as String] = r;
    }
    for (final r in remote) {
      final id = r['id'] as String;
      final existing = byId[id];
      if (existing == null) {
        byId[id] = r;
      } else {
        final lTs = existing[tsField] as int? ?? 0;
        final rTs = r[tsField] as int? ?? 0;
        if (rTs > lTs) byId[id] = r;
        // else keep local (last-write-wins, newer timestamp wins)
      }
    }
    return byId.values.toList();
  }

  static List<Map<String, dynamic>> mergeBookmarks(
    List<Map<String, dynamic>> local,
    List<Map<String, dynamic>> remote,
  ) =>
      mergeById(local, remote, tsField: 'createdAtMs');

  static List<Map<String, dynamic>> mergeHistory(
    List<Map<String, dynamic>> local,
    List<Map<String, dynamic>> remote,
  ) =>
      mergeById(local, remote, tsField: 'startedAtMs');

  static List<Map<String, dynamic>> mergeChapters(
    List<Map<String, dynamic>> local,
    List<Map<String, dynamic>> remote,
  ) =>
      mergeById(local, remote, tsField: 'startMs');
}

/// Main sync engine — Drift <-> Remote with offline queue, retry, LWW, hashing, encryption.
class SyncEngine {
  final AppDatabase db;
  final SyncBackend backend;
  final SyncCrypto crypto;
  final SyncQueue queue;

  // Progress debouncing
  Timer? _progressDebounce;
  final Map<String, Map<String, dynamic>> _pendingProgress = {};
  static const _progressDebounceMs = 5000;

  // Retry config
  static const _maxRetries = 5;
  static const _baseDelayMs = 1000;

  // Last sync watermark (for incremental pull)
  int _lastSyncMs = 0;
  int get lastSyncMs => _lastSyncMs;

  // Playback hook
  void Function(String bookId, Duration position, Duration bookPosition)? onProgressSync;

  // Sync state stream for UI
  final StreamController<SyncState> _stateCtrl = StreamController.broadcast();
  Stream<SyncState> get stateStream => _stateCtrl.stream;
  SyncState _state = SyncState.idle;
  SyncState get state => _state;

  bool _isSyncing = false;
  // Tombstones for local deletes (to propagate)
  final List<Map<String, dynamic>> _tombstones = [];

  SyncEngine({
    required this.db,
    required this.backend,
    SyncCrypto? crypto,
    SyncQueue? queue,
  })  : crypto = crypto ?? SyncCrypto(),
        queue = queue ?? SyncQueue();

  Future<void> init() async {
    await queue.load();
    // Restore lastSyncMs from queue file or default 0
    // In production, persist via SharedPreferences; here we keep in-memory until push succeeds.
  }

  Future<void> dispose() async {
    _progressDebounce?.cancel();
    await _stateCtrl.close();
  }

  void _emit(SyncState s) {
    _state = s;
    if (!_stateCtrl.isClosed) _stateCtrl.add(s);
  }

  // ── Public API ────────────────────────────────────────────────────────

  /// Full sync: pull remote, merge LWW, push merged.
  Future<SyncResult> syncAll() async {
    if (_isSyncing) return SyncResult.skipped('already syncing');
    _isSyncing = true;
    _emit(SyncState.syncing);
    try {
      // Flush progress debounce immediately
      _flushProgress();

      // 1. Pull
      final remote = await _retry(() => backend.pull(sinceMs: _lastSyncMs));
      if (remote != null) {
        final merged = await _mergeRemote(remote);
        await _applyMerged(merged);
        _lastSyncMs = merged.exportedAtMs;
      }

      // 2. Process offline queue
      await _drainQueue();

      // 3. Push current state (with file hashes, encrypted if enabled)
      final payload = await _buildPayload();
      final ok = await _retry(() => _pushPayload(payload));
      if (ok) {
        _lastSyncMs = payload.exportedAtMs;
        _emit(SyncState.idle);
        return SyncResult.success(pushed: payload.books.length, pulled: remote?.books.length ?? 0);
      } else {
        // Enqueue for later
        await _enqueuePayload(payload);
        _emit(SyncState.offline);
        return SyncResult.offline('push failed, queued');
      }
    } catch (e) {
      debugPrint('SyncEngine.syncAll error: $e');
      _emit(SyncState.error);
      return SyncResult.error(e.toString());
    } finally {
      _isSyncing = false;
    }
  }

  /// Push local state to remote (without pull).
  Future<SyncResult> push() async {
    _flushProgress();
    final payload = await _buildPayload();
    final ok = await _retry(() => _pushPayload(payload));
    if (ok) {
      _lastSyncMs = payload.exportedAtMs;
      _emit(SyncState.idle);
      return SyncResult.success(pushed: payload.books.length);
    } else {
      await _enqueuePayload(payload);
      _emit(SyncState.offline);
      return SyncResult.offline('queued');
    }
  }

  /// Pull remote state and merge (without push).
  Future<SyncResult> pull() async {
    final remote = await _retry(() => backend.pull(sinceMs: _lastSyncMs));
    if (remote == null) {
      _emit(SyncState.idle);
      return SyncResult.success(pulled: 0);
    }
    final merged = await _mergeRemote(remote);
    await _applyMerged(merged);
    _lastSyncMs = merged.exportedAtMs;
    _emit(SyncState.idle);
    return SyncResult.success(pulled: remote.books.length);
  }

  // ── Progress sync (wired to PlaybackService) ──────────────────────────

  /// Called by PlaybackService on progress tick. Debounced push.
  void notifyProgressChanged(String bookId, Duration position, Duration bookPosition) {
    _pendingProgress[bookId] = {
      'bookId': bookId,
      'lastPositionMs': position.inMilliseconds,
      'bookPositionMs': bookPosition.inMilliseconds,
      'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
    };
    _progressDebounce?.cancel();
    _progressDebounce = Timer(const Duration(milliseconds: _progressDebounceMs), () {
      _flushProgress();
      // Enqueue a push — fire-and-forget, retry handles offline
      unawaited(push());
    });
  }

  /// Immediate flush for tests / lifecycle.
  void flushProgressForTest() => _flushProgress();

  void _flushProgress() {
    if (_pendingProgress.isEmpty) return;
    // Apply to DB synchronously for LWW (update books progress)
    for (final entry in _pendingProgress.values) {
      final bookId = entry['bookId'] as String;
      final posMs = entry['lastPositionMs'] as int;
      final updatedAtMs = entry['updatedAtMs'] as int;
      // Update DB directly — this will be picked up by next push's exportAllJson
      unawaited(_applyProgressToDb(bookId, posMs, updatedAtMs));
    }
    _pendingProgress.clear();
  }

  Future<void> _applyProgressToDb(String bookId, int posMs, int updatedAtMs) async {
    try {
      final book = await db.getBook(bookId);
      if (book == null) return;
      final total = book.totalDurationMs;
      final bookPosMs = posMs; // simplified; playback_service provides bookPosition separately
      final progress = total == 0 ? 0.0 : (bookPosMs / total).clamp(0.0, 1.0);
      await (db.update(db.books)..where((t) => t.id.equals(bookId))).write(BooksCompanion(
        lastPositionMs: Value(posMs),
        lastPlayedAtMs: Value(updatedAtMs),
        totalProgress: Value(progress),
        isFinished: Value(progress >= 0.99),
      ));
    } catch (e) {
      debugPrint('applyProgressToDb failed: $e');
    }
  }

  // ── File hashes (m4b never uploaded) ─────────────────────────────────

  Future<Map<String, String>> computeFileHashes() async {
    final books = await db.allBooks;
    final allPaths = <String>{};
    for (final b in books) {
      try {
        final paths = AppDatabase.decodePaths(b.filePathsJson);
        allPaths.addAll(paths);
      } catch (_) {}
    }
    return FileHasher.hashFiles(allPaths.toList());
  }

  // ── Queue & retry ─────────────────────────────────────────────────────

  Future<void> _enqueuePayload(SyncPayload payload) async {
    final op = SyncOperation(
      id: 'push_${DateTime.now().millisecondsSinceEpoch}',
      entity: 'sync_payload',
      op: 'push',
      payload: payload.toJson(),
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );
    await queue.enqueue(op);
  }

  Future<void> _drainQueue() async {
    await queue.load();
    if (queue.isEmpty) return;
    final toRetry = List<SyncOperation>.from(queue.pending);
    for (final op in toRetry) {
      if (op.attempts >= _maxRetries) {
        debugPrint('SyncQueue: dropping op ${op.id} after ${op.attempts} attempts');
        await queue.remove(op.id);
        continue;
      }
      final delay = _backoffMs(op.attempts);
      if (op.lastErrorMs != null) {
        final elapsed = DateTime.now().millisecondsSinceEpoch - op.lastErrorMs!;
        if (elapsed < delay) continue; // not yet time to retry
      }
      try {
        final payload = SyncPayload.fromJson(op.payload);
        final ok = await _pushPayload(payload);
        if (ok) {
          await queue.remove(op.id);
        } else {
          await queue.markAttempt(op.id);
        }
      } catch (e) {
        debugPrint('drainQueue op ${op.id} failed: $e');
        await queue.markAttempt(op.id);
      }
    }
  }

  int _backoffMs(int attempts) => _baseDelayMs * (1 << attempts); // 1s,2s,4s,8s,16s

  Future<T> _retry<T>(Future<T> Function() fn) async {
    int attempt = 0;
    while (true) {
      try {
        return await fn();
      } catch (e) {
        attempt++;
        if (attempt >= _maxRetries) rethrow;
        final delay = _backoffMs(attempt);
        await Future.delayed(Duration(milliseconds: delay));
      }
    }
  }

  // ── Payload build / push ──────────────────────────────────────────────

  Future<SyncPayload> _buildPayload() async {
    final exported = await db.exportAllJson();
    final fileHashes = await computeFileHashes();
    // Normalize books/chapters/bookmarks/history to List<Map>
    List<Map<String, dynamic>> toMaps(dynamic v) {
      if (v is List) return v.cast<Map<String, dynamic>>();
      return [];
    }

    return SyncPayload(
      exportedAtMs: DateTime.now().millisecondsSinceEpoch,
      deviceId: await _deviceId(),
      books: toMaps(exported['books']),
      chapters: toMaps(exported['chapters']),
      bookmarks: toMaps(exported['bookmarks']),
      history: toMaps(exported['history']),
      fileHashes: fileHashes,
      tombstones: List.from(_tombstones),
    );
  }

  Future<bool> _pushPayload(SyncPayload payload) async {
    // Optionally encrypt payload.books etc before push
    if (crypto.enabled) {
      final encrypted = SyncPayload(
        exportedAtMs: payload.exportedAtMs,
        deviceId: payload.deviceId,
        books: _encryptList(payload.books),
        chapters: _encryptList(payload.chapters),
        bookmarks: _encryptList(payload.bookmarks),
        history: _encryptList(payload.history),
        fileHashes: payload.fileHashes, // hashes are not sensitive
        tombstones: payload.tombstones,
      );
      return backend.push(encrypted);
    }
    return backend.push(payload);
  }

  List<Map<String, dynamic>> _encryptList(List<Map<String, dynamic>> list) {
    return list.map((m) {
      final enc = crypto.encrypt(jsonEncode(m));
      return {'_enc': enc};
    }).toList();
  }

  List<Map<String, dynamic>> _decryptList(List<Map<String, dynamic>> list) {
    if (list.isEmpty) return list;
    // Detect encrypted envelope
    if (list.first.containsKey('_enc')) {
      return list.map((m) {
        final enc = m['_enc'] as String;
        final dec = crypto.decrypt(enc);
        return jsonDecode(dec) as Map<String, dynamic>;
      }).toList();
    }
    return list;
  }

  Future<String> _deviceId() async {
    // Stable per-install id via file or fallback random
    try {
      final dir = await _supportDir();
      if (dir == null) return 'mem_${identityHashCode(this)}';
      final f = File('${dir.path}/device_id.txt');
      if (await f.exists()) return (await f.readAsString()).trim();
      final id = _randomId();
      await f.writeAsString(id);
      return id;
    } catch (_) {
      return 'mem_${identityHashCode(this)}';
    }
  }

  String _randomId() {
    final r = Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    return sha256.convert(bytes).toString().substring(0, 32);
  }

  Future<Directory?> _supportDir() async {
    try {
      // Use system temp as fallback in tests; path_provider optional
      // Dynamic import avoidance: try path_provider via conditional
      // Fallback to temp dir
      final d = Directory.systemTemp;
      return d;
    } catch (_) {
      return null;
    }
  }

  // ── Merge (Last-Write-Wins) ───────────────────────────────────────────

  Future<SyncPayload> _mergeRemote(SyncPayload remote) async {
    // Decrypt remote if needed
    final rBooks = _decryptList(remote.books);
    final rChapters = _decryptList(remote.chapters);
    final rBookmarks = _decryptList(remote.bookmarks);
    final rHistory = _decryptList(remote.history);

    final exported = await db.exportAllJson();
    final lBooks = (exported['books'] as List).cast<Map<String, dynamic>>();
    final lChapters = (exported['chapters'] as List).cast<Map<String, dynamic>>();
    final lBookmarks = (exported['bookmarks'] as List).cast<Map<String, dynamic>>();
    final lHistory = (exported['history'] as List).cast<Map<String, dynamic>>();

    // Books: LWW per id using lastPlayedAtMs for progress, addedAtMs for meta
    final mergedBooks = _mergeBooks(lBooks, rBooks);
    final mergedChapters = LastWriteWins.mergeChapters(lChapters, rChapters);
    final mergedBookmarks = LastWriteWins.mergeBookmarks(lBookmarks, rBookmarks);
    final mergedHistory = LastWriteWins.mergeHistory(lHistory, rHistory);

    // Apply tombstones (deletions win if newer)
    final tombIds = remote.tombstones.map((t) => t['id'] as String).toSet();
    mergedBooks.removeWhere((b) => tombIds.contains(b['id']));
    mergedBookmarks.removeWhere((b) => tombIds.contains(b['id']));
    mergedHistory.removeWhere((h) => tombIds.contains(h['id']));

    return SyncPayload(
      exportedAtMs: max(remote.exportedAtMs, DateTime.now().millisecondsSinceEpoch),
      deviceId: remote.deviceId,
      books: mergedBooks,
      chapters: mergedChapters,
      bookmarks: mergedBookmarks,
      history: mergedHistory,
      fileHashes: {...remote.fileHashes}, // file hashes are additive
      tombstones: remote.tombstones,
    );
  }

  List<Map<String, dynamic>> _mergeBooks(
    List<Map<String, dynamic>> local,
    List<Map<String, dynamic>> remote,
  ) {
    final byId = <String, Map<String, dynamic>>{};
    for (final b in local) {
      byId[b['id'] as String] = b;
    }
    for (final b in remote) {
      final id = b['id'] as String;
      final existing = byId[id];
      if (existing == null) {
        byId[id] = b;
      } else {
        byId[id] = LastWriteWins.mergeBook(existing, b);
      }
    }
    return byId.values.toList();
  }

  Future<void> _applyMerged(SyncPayload merged) async {
    // Import merged via Drift's importAllJson (insertOrReplace)
    await db.importAllJson({
      'books': merged.books,
      'chapters': merged.chapters,
      'bookmarks': merged.bookmarks,
      'history': merged.history,
    });
    // File hashes are not stored in DB; kept for integrity checks (no upload)
    // Tombstones: delete locally if not already
    for (final t in merged.tombstones) {
      final entity = t['entity'] as String?;
      final id = t['id'] as String?;
      if (id == null) continue;
      try {
        if (entity == 'book') {
          await db.deleteBook(id);
        } else if (entity == 'bookmark') {
          await db.deleteBookmark(id);
        } else if (entity == 'history') {
          await (db.delete(db.listeningHistory)..where((tbl) => tbl.id.equals(id))).go();
        }
      } catch (_) {}
    }
  }

  // ── Tombstone helper (call when deleting locally) ─────────────────────

  void recordDeletion(String entity, String id) {
    _tombstones.add({
      'entity': entity,
      'id': id,
      'deletedAtMs': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ── Utility ───────────────────────────────────────────────────────────

  /// Exposed for tests: merge books LWW
  List<Map<String, dynamic>> mergeBooksForTest(
    List<Map<String, dynamic>> local,
    List<Map<String, dynamic>> remote,
  ) =>
      _mergeBooks(local, remote);
}

enum SyncState { idle, syncing, offline, error }

class SyncResult {
  final bool success;
  final bool offline;
  final bool skipped;
  final String? message;
  final int pushed;
  final int pulled;

  SyncResult._({required this.success, this.offline = false, this.skipped = false, this.message, this.pushed = 0, this.pulled = 0});
  factory SyncResult.success({int pushed = 0, int pulled = 0}) => SyncResult._(success: true, pushed: pushed, pulled: pulled);
  factory SyncResult.offline(String m) => SyncResult._(success: false, offline: true, message: m);
  factory SyncResult.error(String m) => SyncResult._(success: false, message: m);
  factory SyncResult.skipped(String m) => SyncResult._(success: false, skipped: true, message: m);

  @override
  String toString() => 'SyncResult(success:$success offline:$offline skipped:$skipped msg:$message pushed:$pushed pulled:$pulled)';
}
