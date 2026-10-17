import 'dart:async';
import 'dart:io';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import '../../models/playback_state.dart' as m;
import '../db/app_database.dart';
import '../history_service.dart';
import '../library_service.dart';
import '../bookmark_service.dart';

final playbackServiceProvider = Provider<PlaybackService>((ref) => throw UnimplementedError('override in main'));

class PlaybackService {
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
  }

  Future<void> dispose() async {
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
    if (_currentBookId == null) return;
    await _player!.play();
    _startSession();
  }

  Future<void> pause() async {
    await _player!.pause();
    await _persistProgress();
    await _maybeAutoBookmark();
    await _endSession();
  }

  Future<void> stop() async {
    await _player!.stop();
    await _persistProgress();
    await _endSession();
  }

  Future<void> seek(Duration pos) async {
    await _player!.seek(pos);
    await _persistProgress();
  }

  Future<void> seekBook(Duration bookPos) async {
    final book = _currentBookId != null ? await db.getBook(_currentBookId!) : null;
    if (book == null) return;
    final paths = AppDatabase.decodePaths(book.filePathsJson);
    Duration cursor = Duration.zero;
    for (int i=0;i<paths.length;i++) {
      final dur = _player!.sequence?[i]?.duration ?? Duration.zero;
      final next = cursor + dur;
      if (bookPos < next || i==paths.length-1) {
        final offsetInFile = bookPos - cursor;
        // clamp Duration manually
        Duration clamped = offsetInFile;
        if (clamped < Duration.zero) clamped = Duration.zero;
        if (dur != Duration.zero && clamped > dur) clamped = dur;
        await _player!.seek(clamped, index: i);
        return;
      }
      cursor = next;
    }
  }

  Future<void> skipForward([int sec = 30]) async {
    final pos = _player!.position + Duration(seconds: sec);
    await seek(pos);
  }

  Future<void> skipBack([int sec = 30]) async {
    final pos = _player!.position - Duration(seconds: sec);
    await seek(pos < Duration.zero ? Duration.zero : pos);
  }

  Future<void> setSpeed(double s) async {
    await _player!.setSpeed(s);
    _emit(state.copyWith(speed: s));
  }

  Future<void> setVolume(double v) async {
    await _player!.setVolume(v);
    _emit(state.copyWith(volume: v));
  }

  Future<void> nextTrack() async { if (_player!.hasNext) await _player!.seekToNext(); }
  Future<void> previousTrack() async { if (_player!.hasPrevious) await _player!.seekToPrevious(); }

  void setSleepTimer(Duration d, {bool endOfChapter = false}) {
    _sleepTimer?.cancel();
    _sleepRemaining = d;
    if (d == Duration.zero) return;
    _sleepTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      _sleepRemaining -= const Duration(seconds: 1);
      if (_sleepRemaining <= Duration.zero) {
        pause();
        t.cancel();
      }
    });
  }

  void cancelSleepTimer() { _sleepTimer?.cancel(); _sleepRemaining = Duration.zero; }
  Duration get sleepRemaining => _sleepRemaining;

  Future<String> addManualBookmark({String? title, String? note}) async {
    if (_currentBookId == null) throw StateError('No book loaded');
    final pos = _player!.position;
    final bookPos = _bookPosition();
    final file = _currentQueue.isNotEmpty ? _currentQueue[_currentIndex] : '';
    return bookmarks.addManual(bookId: _currentBookId!, filePath: file, position: pos, bookPosition: bookPos, title: title, note: note);
  }

  void _onPosition(Duration pos) => _emit(state.copyWith(position: pos));

  void _onPlayerState(PlayerState ps) {
    final st = ps.toStatus();
    _emit(state.copyWith(status: st));
    if (st == m.PlaybackStatus.completed) _onCompleted();
  }

  Future<void> _onCompleted() async {
    await _persistProgress();
    await _endSession();
  }

  Duration _bookPosition() => _currentBookOffset + _player!.position;

  void _recalcBookOffset() {
    Duration sum = Duration.zero;
    for (int i=0;i<_currentIndex;i++) {
      final d = _player!.sequence?[i]?.duration;
      if (d != null) sum += d;
    }
    _currentBookOffset = sum;
  }

  void _emit(m.PlaybackState s) {
    _state = s;
    _stateCtrl.add(s);
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
      final pos = _player!.position;
      if (pos == Duration.zero) return;
      final bookPos = _bookPosition();
      final file = _currentQueue[_currentIndex];
      await bookmarks.addAuto(bookId: _currentBookId!, filePath: file, position: pos, bookPosition: bookPos);
      await bookmarks.pruneAuto(_currentBookId!);
    } catch (_) {}
  }

  void _startSession() {
    if (_activeSessionId != null) return;
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
}
