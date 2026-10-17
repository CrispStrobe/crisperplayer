import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/providers.dart';
import 'sync_engine.dart';

/// Riverpod provider for SyncEngine + SyncService.
///
/// Wires PlaybackService progress sync (notifyProgressChanged) so that
/// playback position is debounced and pushed via SyncEngine.
///
/// Supports Supabase REST or Firebase via environment / settings.
/// Defaults to in-memory backend (no remote) until configured.

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final db = ref.watch(appDatabaseProvider);
  // Default to memory backend; override via syncBackendProvider for real remote.
  final backend = ref.watch(syncBackendProvider);
  final crypto = ref.watch(syncCryptoProvider);
  final queue = SyncQueue(); // memory queue; for persistent, pass filePath
  final engine = SyncEngine(db: db, backend: backend, crypto: crypto, queue: queue);
  ref.onDispose(() => engine.dispose());
  unawaited(engine.init());
  return engine;
});

/// Backend provider — override in main.dart with real Supabase/Firebase config.
final syncBackendProvider = Provider<SyncBackend>((ref) {
  // Try to read from environment or settings; fallback to memory.
  // For production, override with:
  //   SupabaseSyncBackend(supabaseUrl: '...', anonKey: '...', userId: '...')
  //   FirebaseSyncBackend(databaseUrl: '...', userId: '...', authToken: '...')
  return MemorySyncBackend();
});

final syncCryptoProvider = Provider<SyncCrypto>((ref) {
  // Override with SyncCrypto(passphrase: 'user-passphrase') for envelope encryption.
  // Passphrase can come from SettingsService or secure storage.
  return SyncCrypto();
});

/// High-level service that binds PlaybackService -> SyncEngine.
class SyncServiceBridge {
  final SyncEngine engine;
  final dynamic playback;
  StreamSubscription? _playbackSub;
  Timer? _syncTimer;

  SyncServiceBridge({required this.engine, required this.playback});

  Future<void> init() async {
    await engine.init();
    // Direct hook: PlaybackService._persistProgress -> engine.notifyProgressChanged (debounced, offline queue)
    try {
      playback.onProgressSync = (String bookId, Duration pos, Duration bookPos) {
        engine.notifyProgressChanged(bookId, pos, bookPos);
      };
    } catch (_) {}
    // Fallback: also listen to stateStream for progress (covers external state changes)
    try {
      final stream = playback.stateStream as Stream;
      _playbackSub = stream.listen((s) {
        final bookId = playback.currentBookId as String?;
        if (bookId == null) return;
        try {
          final pos = s.position as Duration;
          if (pos == Duration.zero) return;
          final bookPos = playback.bookPosition as Duration;
          engine.notifyProgressChanged(bookId, pos, bookPos);
        } catch (_) {}
      });
    } catch (e) {
      debugPrint('SyncServiceBridge init stream failed: $e');
    }

    // Periodic sync every 5 minutes when online
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      try {
        await engine.syncAll();
      } catch (e) {
        debugPrint('SyncServiceBridge periodic sync failed: $e');
      }
    });
  }

  Future<void> dispose() async {
    try {
      playback.onProgressSync = null;
    } catch (_) {}
    await _playbackSub?.cancel();
    _syncTimer?.cancel();
  }

  Future<SyncResult> syncNow() => engine.syncAll();
  Future<SyncResult> pushNow() => engine.push();
  Future<SyncResult> pullNow() => engine.pull();

  /// Call when user changes passphrase / enables encryption.
  void updateCrypto(String? passphrase) {
    // Note: crypto is immutable in SyncEngine; for passphrase change,
    // re-create engine via provider override or ref.invalidate.
    debugPrint('SyncServiceBridge.updateCrypto: recreate provider with new passphrase');
  }
}

final syncServiceBridgeProvider = Provider<SyncServiceBridge>((ref) {
  final engine = ref.watch(syncEngineProvider);
  final playback = ref.watch(playbackProvider);
  final svc = SyncServiceBridge(engine: engine, playback: playback);
  ref.onDispose(() => svc.dispose());
  unawaited(svc.init());
  return svc;
});
