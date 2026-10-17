import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sync status for UI.
enum SyncStatus { idle, syncing, success, error, offline }

extension SyncStatusX on SyncStatus {
  String get label => switch (this) {
        SyncStatus.idle => 'Idle',
        SyncStatus.syncing => 'Syncing…',
        SyncStatus.success => 'Up to date',
        SyncStatus.error => 'Sync failed',
        SyncStatus.offline => 'Offline',
      };
}

/// Conflict resolution strategy.
enum ConflictStrategy { keepLocal, keepRemote, keepNewest, askEachTime }

extension ConflictStrategyX on ConflictStrategy {
  String get label => switch (this) {
        ConflictStrategy.keepLocal => 'Keep local',
        ConflictStrategy.keepRemote => 'Keep cloud',
        ConflictStrategy.keepNewest => 'Keep newest (recommended)',
        ConflictStrategy.askEachTime => 'Ask each time',
      };
  String get description => switch (this) {
        ConflictStrategy.keepLocal => 'Local progress always wins',
        ConflictStrategy.keepRemote => 'Cloud progress always wins',
        ConflictStrategy.keepNewest => 'Newer timestamp wins',
        ConflictStrategy.askEachTime => 'Show a prompt on conflict',
      };
}

/// Mock conflict entry for the resolution UI.
class SyncConflict {
  final String id;
  final String bookTitle;
  final String field; // e.g. "Progress", "Bookmark"
  final String localValue;
  final String remoteValue;
  final DateTime localTime;
  final DateTime remoteTime;

  const SyncConflict({
    required this.id,
    required this.bookTitle,
    required this.field,
    required this.localValue,
    required this.remoteValue,
    required this.localTime,
    required this.remoteTime,
  });
}

/// Central sync state — persisted in SharedPreferences so it survives restarts.
/// Supabase auth is represented as a placeholder: email/password stored locally
/// and validated; swapping in real supabase_flutter is a one-line change in [signIn].
class SyncService extends ChangeNotifier {
  final SharedPreferences _prefs;

  SyncService(this._prefs);

  static const _kEnabled = 'sync_enabled';
  static const _kEmail = 'sync_email';
  static const _kToken = 'sync_token';
  static const _kLastSyncMs = 'sync_last_sync_ms';
  static const _kConflictIdx = 'sync_conflict_strategy';
  static const _kAutoSync = 'sync_auto';
  static const _kLastStatus = 'sync_last_status';
  static const _kLastError = 'sync_last_error';

  // -- persisted getters/setters --

  bool get syncEnabled => _prefs.getBool(_kEnabled) ?? false;
  set syncEnabled(bool v) {
    _prefs.setBool(_kEnabled, v);
    notifyListeners();
  }

  bool get autoSync => _prefs.getBool(_kAutoSync) ?? true;
  set autoSync(bool v) {
    _prefs.setBool(_kAutoSync, v);
    notifyListeners();
  }

  String? get accountEmail => _prefs.getString(_kEmail);
  bool get isLoggedIn => accountEmail != null && accountEmail!.isNotEmpty;
  String? get authToken => _prefs.getString(_kToken);

  ConflictStrategy get conflictStrategy {
    final idx = _prefs.getInt(_kConflictIdx) ?? ConflictStrategy.keepNewest.index;
    if (idx < 0 || idx >= ConflictStrategy.values.length) return ConflictStrategy.keepNewest;
    return ConflictStrategy.values[idx];
  }

  set conflictStrategy(ConflictStrategy v) {
    _prefs.setInt(_kConflictIdx, v.index);
    notifyListeners();
  }

  DateTime? get lastSyncTime {
    final ms = _prefs.getInt(_kLastSyncMs);
    if (ms == null || ms == 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  SyncStatus get lastStatus {
    final s = _prefs.getString(_kLastStatus);
    if (s == null) return SyncStatus.idle;
    return SyncStatus.values.firstWhere((e) => e.name == s, orElse: () => SyncStatus.idle);
  }

  String? get lastError => _prefs.getString(_kLastError);

  // -- transient state --

  SyncStatus _status = SyncStatus.idle;
  SyncStatus get status => _status;

  bool get isSyncing => _status == SyncStatus.syncing;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  double _progress = 0; // 0..1 for manual sync progress bar
  double get progress => _progress;

  /// Mock pending conflicts (shown when strategy == askEachTime or on demand).
  List<SyncConflict> _pendingConflicts = [];
  List<SyncConflict> get pendingConflicts => List.unmodifiable(_pendingConflicts);

  void _setStatus(SyncStatus s, {String? error}) {
    _status = s;
    _errorMessage = error;
    _prefs.setString(_kLastStatus, s.name);
    if (error != null) {
      _prefs.setString(_kLastError, error);
    } else if (s != SyncStatus.error) {
      _prefs.remove(_kLastError);
    }
    notifyListeners();
  }

  // -- auth (placeholder for Supabase) --

  /// Placeholder sign-in — validates email format and stores token locally.
  /// Replace body with `await Supabase.instance.client.auth.signInWithPassword(...)`
  /// when supabase_flutter is added.
  Future<bool> signIn({required String email, required String password}) async {
    if (email.trim().isEmpty || !email.contains('@')) {
      _setStatus(SyncStatus.error, error: 'Invalid email address');
      return false;
    }
    if (password.length < 6) {
      _setStatus(SyncStatus.error, error: 'Password must be at least 6 characters');
      return false;
    }
    // Simulate network delay
    _setStatus(SyncStatus.syncing);
    await Future.delayed(const Duration(milliseconds: 900));

    // Simple local mock: any valid email+password succeeds.
    // Real implementation: call Supabase and handle AuthException.
    await _prefs.setString(_kEmail, email.trim());
    await _prefs.setString(_kToken, 'mock_token_${DateTime.now().millisecondsSinceEpoch}');
    _setStatus(SyncStatus.idle);
    // Generate demo conflicts on login
    _seedDemoConflicts();
    notifyListeners();
    return true;
  }

  /// OAuth placeholder (Google/Apple) — stores email directly.
  Future<bool> signInWithProvider(String provider) async {
    _setStatus(SyncStatus.syncing);
    await Future.delayed(const Duration(milliseconds: 700));
    // Mock provider email
    await _prefs.setString(_kEmail, 'user@$provider.example.com');
    await _prefs.setString(_kToken, 'mock_oauth_${provider}_${DateTime.now().millisecondsSinceEpoch}');
    _setStatus(SyncStatus.idle);
    _seedDemoConflicts();
    notifyListeners();
    return true;
  }

  Future<void> signOut() async {
    await _prefs.remove(_kEmail);
    await _prefs.remove(_kToken);
    await _prefs.remove(_kLastSyncMs);
    _pendingConflicts = [];
    _setStatus(SyncStatus.idle);
    notifyListeners();
  }

  // -- sync operations --

  /// Manual sync — simulates upload/download with progress.
  Future<void> syncNow() async {
    if (!syncEnabled && isLoggedIn) {
      // Allow manual sync even if toggle off — just inform.
    }
    if (!isLoggedIn) {
      _setStatus(SyncStatus.error, error: 'Not signed in');
      return;
    }
    _setStatus(SyncStatus.syncing);
    _progress = 0;
    notifyListeners();

    try {
      // Simulate staged sync: upload local -> download remote -> resolve
      for (int i = 1; i <= 5; i++) {
        await Future.delayed(const Duration(milliseconds: 280));
        _progress = i / 5;
        notifyListeners();
      }
      // Mock occasional offline error (5% chance) — disabled for determinism in tests
      // final isOffline = Random().nextDouble() < 0.05;

      await _prefs.setInt(_kLastSyncMs, DateTime.now().millisecondsSinceEpoch);
      _progress = 1;
      _setStatus(SyncStatus.success);
      // Clear resolved demo conflicts after successful sync (unless askEachTime)
      if (conflictStrategy != ConflictStrategy.askEachTime) {
        _pendingConflicts = [];
      }
      notifyListeners();
      // Reset to idle after 2s so UI shows success briefly
      Future.delayed(const Duration(seconds: 2), () {
        if (_status == SyncStatus.success) {
          _setStatus(SyncStatus.idle);
        }
      });
    } catch (e) {
      _setStatus(SyncStatus.error, error: e.toString());
    }
  }

  Future<void> toggleSync(bool enabled) async {
    syncEnabled = enabled;
    if (enabled && isLoggedIn) {
      // Optionally auto-sync on enable
      if (autoSync) {
        unawaited(syncNow());
      }
    }
  }

  // -- conflict resolution --

  void _seedDemoConflicts() {
    final now = DateTime.now();
    _pendingConflicts = [
      SyncConflict(
        id: 'c1',
        bookTitle: 'Dune — Frank Herbert',
        field: 'Playback position',
        localValue: '12:34 / Ch. 5',
        remoteValue: '18:02 / Ch. 6',
        localTime: now.subtract(const Duration(hours: 2)),
        remoteTime: now.subtract(const Duration(minutes: 30)),
      ),
      SyncConflict(
        id: 'c2',
        bookTitle: 'Project Hail Mary',
        field: 'Bookmark “Important”',
        localValue: '01:15:00 — with note',
        remoteValue: '01:14:42 — no note',
        localTime: now.subtract(const Duration(days: 1)),
        remoteTime: now.subtract(const Duration(hours: 5)),
      ),
    ];
  }

  /// Resolve a single conflict.
  void resolveConflict(String conflictId, {required bool keepLocal}) {
    _pendingConflicts.removeWhere((c) => c.id == conflictId);
    // In real impl: write chosen version to DB + mark for upload.
    notifyListeners();
    if (_pendingConflicts.isEmpty) {
      // All resolved -> sync
      unawaited(syncNow());
    }
  }

  /// Resolve all with strategy.
  void resolveAllConflicts(ConflictStrategy strategy) {
    conflictStrategy = strategy;
    _pendingConflicts = [];
    notifyListeners();
    unawaited(syncNow());
  }

  void dismissConflict(String conflictId) {
    _pendingConflicts.removeWhere((c) => c.id == conflictId);
    notifyListeners();
  }

  // For testing / debugging: inject a conflict.
  void addDemoConflict() {
    _seedDemoConflicts();
    notifyListeners();
  }
}

/// Riverpod provider for SyncService — overridden in main.dart.
final syncServiceProvider = ChangeNotifierProvider<SyncService>((ref) {
  throw UnimplementedError('syncServiceProvider not overridden — provide in main.dart');
});
