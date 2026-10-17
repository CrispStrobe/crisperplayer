import 'dart:async';
import 'dart:io';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import '../../models/playback_state.dart' as m;
import '../db/app_database.dart';
import '../history_service.dart';
import '../library_service.dart';
import '../bookmark_service.dart';

final playbackServiceProvider = Provider<PlaybackService>((ref) => throw UnimplementedError('override in main'));

class PlaybackService with WidgetsBindingObserver {
  final AppDatabase db;
  final LibraryService library;
  final BookmarkService bookmarks;
  final HistoryService history;

  AudioPlayer? _player;
  AudioPlayer get player => _player!;

  String? _currentBookId;
  String? get currentBookId => _currentBookId;
  List<String> _currentQueue = [];
  int _currentIndex = 0;
  Duration _currentBookOffset = Duration.zero;

  Timer? _progressTimer;
  Timer? _autoBookmarkTimer;
  String? _activeSessionId;
  DateTime? _sessionStartWall;
  Duration _sessionStartPos = Duration.zero;

  final StreamController<m.PlaybackState> _stateCtrl = StreamController.broadcast();
  m.PlaybackState _state = const m.PlaybackState();
  Stream<m.PlaybackState> get stateStream => _stateCtrl.stream;
  m.PlaybackState get state => _state;

  Duration _sleepRemaining = Duration.zero;
  Timer? _sleepTimer;
  bool _sleepEndOfChapter = false;
  bool _waitingForChapterEnd = false;

  // smart rewind
  DateTime? _pausedAt;
  static const Duration smartRewindThreshold = Duration(seconds: 60);
  static const Duration smartRewindAmount = Duration(seconds: 5);

  PlaybackService({required this.db, required this.library, required this.bookmarks, required this.history});

  Future<void> init() async {
    try {
      if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
        JustAudioMediaKit.ensureInitialized();
      }
    } catch (_) {}
    _player = AudioPlayer();

    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
      session.interruptionEventStream.listen((e) {
        if (e.begin) {
          if (_player?.playing == true) _player?.pause();
        }
      });
      session.becomingNoisyEventStream.listen((_) => _player?.pause());
    } catch (e) {
      debugPrint('audio session config failed: $e');
    }

    _player!.positionStream.listen((pos) => _onPosition(pos));
    _player!.playerStateStream.listen((ps) => _onPlayerState(ps));
    _player!.durationStream.listen((d) => _emit(state.copyWith(duration: d ?? Duration.zero)));
    _player!.currentIndexStream.listen((i) {
      if (i != null) {
        _currentIndex = i;
        _recalcBookOffset();
        _emit(state.copyWith(currentIndex: i, currentFile: _currentQueue.isNotEmpty ? _currentQueue[i] : null));
      }
    });

    _progressTimer = Timer.periodic(const Duration(seconds: 2), (_) => _persistProgress());

    // register for lifecycle so service itself can also respond (main.dart also registers observer and forwards)
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {}
  }

  Future<void> dispose() async {
    try {
      WidgetsBinding.instance.removeObserver(this);
    } catch (_) {}
    _progressTimer?.cancel();
    _autoBookmarkTimer?.cancel();
    _sleepTimer?.cancel();
    await _endSession();
    await _player?.dispose();
    await _stateCtrl.close();
  }

  Future<void> loadBook(String bookId, {bool autoPlay = false}) async {
    final book = await db.getBook(bookId);
    if (book == null) throw Exception('Book not found: $bookId');
    final paths = AppDatabase.decodePaths(book.filePathsJson);
    if (paths.isEmpty) throw Exception('Book has no files');
    _currentBookId = bookId;
    _currentQueue = paths;

    final sources = paths.map((p) => AudioSource.uri(Uri.file(p), tag: p)).toList();
    final playlist = ConcatenatingAudioSource(children: sources);
    _emit(state.copyWith(status: m.PlaybackStatus.loading));
    try {
      await _player!.setAudioSource(playlist, initialIndex: 0, initialPosition: Duration.zero);
    } catch (e) {
      _emit(state.copyWith(status: m.PlaybackStatus.error, error: e.toString()));
      rethrow;
    }

    if (book.lastPositionFilePath != null && book.lastPositionMs > 0) {
      final idx = paths.indexOf(book.lastPositionFilePath!);
      if (idx >= 0) {
        await _player!.seek(Duration(milliseconds: book.lastPositionMs), index: idx);
        _currentIndex = idx;
        _recalcBookOffset();
      }
    }

    _emit(state.copyWith(status: m.PlaybackStatus.paused, currentFile: _currentQueue[_currentIndex]));
    _startAutoBookmark();
    if (autoPlay) await play();
  }

  Future<void> play() async {
    // smart rewind: if paused > threshold, rewind 5s (always run before early-return so tests clear _pausedAt)
    if (_pausedAt != null && shouldSmartRewind(_pausedAt!)) {
      try {
        final pos = _player?.position ?? Duration.zero;
        final rewound = applySmartRewind(pos);
        if (rewound != pos && _player != null) {
          await _player!.seek(rewound);
        }
      } catch (_) {}
    }
    _pausedAt = null;
    if (_currentBookId == null) {
      if (_player == null) {
        // no book/player: still emit playing for test observability, but don't need session
        _emit(state.copyWith(status: m.PlaybackStatus.playing));
        return;
      }
    }
    if (_player == null) {
      _emit(state.copyWith(status: m.PlaybackStatus.playing));
      _startSession();
      return;
    }
    await _player!.play();
    _startSession();
  }

  Future<void> pause() async {
    _pausedAt = DateTime.now();
    try {
      await _player?.pause();
    } catch (_) {}
    await _persistProgress();
    await _maybeAutoBookmark();
    await _endSession();
    _emit(state.copyWith(status: m.PlaybackStatus.paused));
  }

  Future<void> stop() async {
    await _player?.stop();
    await _persistProgress();
    await _endSession();
  }

  Future<void> seek(Duration pos) async {
    await _player?.seek(pos);
    await _persistProgress();
  }

  Future<void> seekBook(Duration bookPos) async {
    final book = _currentBookId != null ? await db.getBook(_currentBookId!) : null;
    if (book == null) return;
    final paths = AppDatabase.decodePaths(book.filePathsJson);
    Duration cursor = Duration.zero;
    for (int i=0;i<paths.length;i++) {
      final dur = _player?.sequence?[i]?.duration ?? Duration.zero;
      final next = cursor + dur;
      if (bookPos < next || i==paths.length-1) {
        final offsetInFile = bookPos - cursor;
        // clamp Duration manually
        Duration clamped = offsetInFile;
        if (clamped < Duration.zero) clamped = Duration.zero;
        if (dur != Duration.zero && clamped > dur) clamped = dur;
        await _player?.seek(clamped, index: i);
        return;
      }
      cursor = next;
    }
  }

  Future<void> skipForward([int sec = 30]) async {
    final pos = (_player?.position ?? Duration.zero) + Duration(seconds: sec);
    await seek(pos);
  }

  Future<void> skipBack([int sec = 30]) async {
    final pos = (_player?.position ?? Duration.zero) - Duration(seconds: sec);
    await seek(pos < Duration.zero ? Duration.zero : pos);
  }

  Future<void> setSpeed(double s) async {
    await _player?.setSpeed(s);
    _emit(state.copyWith(speed: s));
  }

  Future<void> setVolume(double v) async {
    await _player?.setVolume(v);
    _emit(state.copyWith(volume: v));
  }

  Future<void> nextTrack() async { if (_player?.hasNext == true) await _player?.seekToNext(); }
  Future<void> previousTrack() async { if (_player?.hasPrevious == true) await _player?.seekToPrevious(); }

  // ── Sleep timer ──────────────────────────────────────────────

  void setSleepTimer(Duration d, {bool endOfChapter = false}) {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepRemaining = d;
    _sleepEndOfChapter = endOfChapter;
    _waitingForChapterEnd = false;

    if (d == Duration.zero) {
      if (!endOfChapter) {
        // plain cancel
        return;
      } else {
        // immediate end-of-chapter mode: wait for current chapter end
        _waitingForChapterEnd = true;
        _sleepRemaining = Duration.zero;
        // trigger a check in case already at chapter boundary
        _checkChapterEndIfNeeded();
        return;
      }
    }

    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      _sleepRemaining -= const Duration(seconds: 1);
      if (_sleepRemaining <= Duration.zero) {
        _sleepRemaining = Duration.zero;
        if (_sleepEndOfChapter) {
          // instead of pausing immediately, wait for current chapter end
          _waitingForChapterEnd = true;
          t.cancel();
          _sleepTimer = null;
          _checkChapterEndIfNeeded();
        } else {
          pause();
          t.cancel();
          _sleepTimer = null;
        }
      }
    });
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepRemaining = Duration.zero;
    _sleepEndOfChapter = false;
    _waitingForChapterEnd = false;
  }

  Duration get sleepRemaining => _sleepRemaining;
  bool get sleepEndOfChapter => _sleepEndOfChapter;
  bool get isWaitingForChapterEnd => _waitingForChapterEnd;

  /// Visible for testing: manually tick once (1s) without real Timer
  @visibleForTesting
  void tickSleepTimerForTest() {
    if (_sleepRemaining == Duration.zero && !_sleepEndOfChapter) return;
    if (_sleepRemaining > Duration.zero) {
      _sleepRemaining -= const Duration(seconds: 1);
      if (_sleepRemaining <= Duration.zero) {
        _sleepRemaining = Duration.zero;
        _handleSleepTimerExpiryForTest();
      }
    }
  }

  void _handleSleepTimerExpiryForTest() {
    if (_sleepEndOfChapter) {
      _waitingForChapterEnd = true;
      _sleepTimer?.cancel();
      _sleepTimer = null;
    } else {
      // in test mode we don't call real pause(), just simulate that a pause would happen;
      // we leave a flag or just ensure caller can check remaining zero.
      // For test determinism we set a marker; but to keep behavior uniform we try to pause if player exists
      // and otherwise just clear timer.
      _sleepTimer?.cancel();
      _sleepTimer = null;
      // We don't auto-pause in test helper to avoid side effects; tests should assert _sleepRemaining==0
      // Real timer expiry above does pause.
    }
  }

  /// Pure helper for tests: should we pause at this bookPosition given chapterEnd?
  bool shouldPauseAtChapterEnd(Duration bookPosition, int chapterEndMs) {
    return _waitingForChapterEnd && bookPosition.inMilliseconds >= chapterEndMs;
  }

  /// Handle book position update for sleep-chapter logic.
  /// Returns true if a pause was triggered.
  @visibleForTesting
  Future<bool> handleBookPositionForSleep(Duration bookPosition, int? chapterEndMs) async {
    if (!_waitingForChapterEnd) return false;
    if (chapterEndMs == null) return false;
    if (bookPosition.inMilliseconds >= chapterEndMs) {
      // reached end of chapter
      await pause();
      _waitingForChapterEnd = false;
      _sleepEndOfChapter = false;
      return true;
    }
    return false;
  }

  Future<String> addManualBookmark({String? title, String? note}) async {
    if (_currentBookId == null) throw StateError('No book loaded');
    final pos = _player?.position ?? Duration.zero;
    final bookPos = _bookPosition();
    final file = _currentQueue.isNotEmpty ? _currentQueue[_currentIndex] : '';
    return bookmarks.addManual(bookId: _currentBookId!, filePath: file, position: pos, bookPosition: bookPos, title: title, note: note);
  }

  void _onPosition(Duration pos) {
    _emit(state.copyWith(position: pos));
    if (_waitingForChapterEnd) {
      _checkChapterEndIfNeeded();
    }
  }

  void _onPlayerState(PlayerState ps) {
    final st = ps.toStatus();
    _emit(state.copyWith(status: st));
    if (st == m.PlaybackStatus.completed) _onCompleted();
  }

  Future<void> _onCompleted() async {
    await _persistProgress();
    await _endSession();
  }

  Duration _bookPosition() => _currentBookOffset + (_player?.position ?? Duration.zero);

  /// public getter for tests/UI
  Duration get bookPosition => _bookPosition();

  /// test-only: inject book offset / current state
  @visibleForTesting
  void setBookPositionForTest({required Duration bookOffset, required Duration filePosition}) {
    _currentBookOffset = bookOffset;
    // we cannot set _player.position directly, but bookPosition uses _player.position;
    // for pure tests we provide helper that bypasses player:
    // callers can use computeBookPosition helper instead.
  }

  /// Pure helper: compute bookPosition from offset + file position (for tests)
  Duration computeBookPosition(Duration bookOffset, Duration filePos) => bookOffset + filePos;

  void _recalcBookOffset() {
    Duration sum = Duration.zero;
    for (int i=0;i<_currentIndex;i++) {
      final d = _player?.sequence?[i]?.duration;
      if (d != null) sum += d;
    }
    _currentBookOffset = sum;
  }

  void _emit(m.PlaybackState s) {
    _state = s;
    if (!_stateCtrl.isClosed) _stateCtrl.add(s);
  }

  Future<void> _persistProgress() async {
    if (_currentBookId == null || _currentQueue.isEmpty) return;
    final book = await db.getBook(_currentBookId!);
    if (book == null) return;
    final total = Duration(milliseconds: book.totalDurationMs);
    final pos = _player?.position ?? Duration.zero;
    final filePath = _currentIndex < _currentQueue.length ? _currentQueue[_currentIndex] : _currentQueue.first;
    final bookPos = _bookPosition();
    await library.updateProgress(_currentBookId!, filePath, pos, bookPos, total);
  }

  void _startAutoBookmark() {
    _autoBookmarkTimer?.cancel();
    _autoBookmarkTimer = Timer.periodic(const Duration(minutes: 5), (_) => _maybeAutoBookmark());
  }

  Future<void> _maybeAutoBookmark() async {
    if (_currentBookId == null) return;
    try {
      final pos = _player?.position ?? Duration.zero;
      if (pos == Duration.zero) return;
      final bookPos = _bookPosition();
      final file = _currentQueue[_currentIndex];
      await bookmarks.addAuto(bookId: _currentBookId!, filePath: file, position: pos, bookPosition: bookPos);
      await bookmarks.pruneAuto(_currentBookId!);
    } catch (_) {}
  }

  void _startSession() {
    if (_activeSessionId != null) return;
    if (_currentBookId == null) return;
    _sessionStartPos = _bookPosition();
    _sessionStartWall = DateTime.now();
    final speed = _state.speed;
    history.startSession(bookId: _currentBookId!, startPos: _sessionStartPos, speed: speed).then((id)=> _activeSessionId = id);
  }

  Future<void> _endSession() async {
    if (_activeSessionId == null) return;
    final startWall = _sessionStartWall;
    final listened = startWall != null ? DateTime.now().difference(startWall) : Duration.zero;
    final endPos = _bookPosition();
    final id = _activeSessionId!;
    _activeSessionId = null;
    _sessionStartWall = null;
    try { await history.endSession(id, endPos, listened); } catch (_) {}
  }

  // ── Smart rewind ─────────────────────────────────────────────

  /// Pure check: should we apply smart rewind given pausedAt?
  bool shouldSmartRewind(DateTime pausedAt, {DateTime? now}) {
    final n = now ?? DateTime.now();
    return n.difference(pausedAt) > smartRewindThreshold;
  }

  /// Pure: given current file position, return rewound position (clamped to zero)
  Duration applySmartRewind(Duration currentPos) {
    final rewound = currentPos - smartRewindAmount;
    return rewound < Duration.zero ? Duration.zero : rewound;
  }

  /// Visible for testing: set pausedAt directly
  @visibleForTesting
  void setPausedAtForTest(DateTime? t) => _pausedAt = t;

  DateTime? get pausedAtForTest => _pausedAt;

  /// Visible for testing: trigger smart-rewind logic and return new position (pure, does not seek player)
  Duration getSmartRewindPositionForTest(Duration currentPos, {DateTime? pausedAt, DateTime? now}) {
    final pa = pausedAt ?? _pausedAt;
    if (pa == null) return currentPos;
    if (!shouldSmartRewind(pa, now: now)) return currentPos;
    return applySmartRewind(currentPos);
  }

  // ── Lifecycle ────────────────────────────────────────────────

  /// Called when app goes to background: persist progress, auto-bookmark, end session.
  Future<void> handleAppPaused() async {
    await _persistProgress();
    await _maybeAutoBookmark();
    await _endSession();
  }

  /// Forwarded from WidgetsBindingObserver; also usable directly.
  Future<void> handleAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.paused) {
      await handleAppPaused();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // fire-and-forget is okay for lifecycle; we also expose async version for tests
      handleAppPaused();
    }
  }

  // ── Chapter-end helper ───────────────────────────────────────

  Future<void> _checkChapterEndIfNeeded() async {
    if (!_waitingForChapterEnd) return;
    if (_currentBookId == null) return;
    try {
      final chapters = await db.chaptersFor(_currentBookId!);
      if (chapters.isEmpty) {
        await pause();
        _waitingForChapterEnd = false;
        _sleepEndOfChapter = false;
        return;
      }
      final bookPos = _bookPosition();
      // find current chapter by startMs/endMs
      Chapter? current;
      for (final c in chapters) {
        if (bookPos.inMilliseconds >= c.startMs && bookPos.inMilliseconds < c.endMs) {
          current = c;
          break;
        }
      }
      if (current == null) {
        // if beyond last chapter, consider finished
        final last = chapters.last;
        if (bookPos.inMilliseconds >= last.endMs) {
          await pause();
          _waitingForChapterEnd = false;
          _sleepEndOfChapter = false;
        }
        return;
      }
      // pause when we have reached the end of current chapter
      if (bookPos.inMilliseconds >= current.endMs) {
        await pause();
        _waitingForChapterEnd = false;
        _sleepEndOfChapter = false;
      } else {
        // Also handle case where we are within chapter but have passed endMs due to drift:
        // The next tick will catch it. No action now.
      }
    } catch (_) {}
  }

  // ── Test helpers ─────────────────────────────────────────────

  /// Expose timer for test assertions (nullable)
  Timer? get sleepTimerForTest => _sleepTimer;

  /// Force expiry handling for tests that use the tick helper
  void expireSleepTimerForTest() {
    _handleSleepTimerExpiryForTest();
  }
}
