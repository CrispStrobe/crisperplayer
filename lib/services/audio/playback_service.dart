import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import '../../models/playback_state.dart' as m;
import '../db/app_database.dart';
import '../history_service.dart';
import '../library_service.dart';
import '../bookmark_service.dart';
import '../settings_service.dart';
import 'audio_backend.dart';
import 'audio_handler.dart';

/// Owns playback commands, persistence and listening sessions. UI and remote
/// controls both enter through this coordinator. Commands execute in order.
class PlaybackService with WidgetsBindingObserver {
  final AppDatabase db;
  final LibraryService library;
  final BookmarkService bookmarks;
  final HistoryService history;
  final SettingsService? settings;
  final DateTime Function() now;
  final AudioPlayer? _externalPlayer;
  AudioBackend? _backend;
  AudioSession? _audioSession;
  CrisperAudioHandler? _audioHandler;
  CrisperAudioHandler? get audioHandler => _audioHandler;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Future<void> _commands = Future.value();
  Future<void>? _initializing;
  bool _disposed = false;
  bool _loading = false;
  bool _wasPlayingBeforeInterruption = false;
  bool _observing = false;
  String? _currentBookId;
  String? get currentBookId => _currentBookId;
  List<BookTrack> _tracks = [];
  List<Chapter> _chapters = [];
  int get _index => _backend?.currentIndex ?? 0;
  Duration get _position => _backend?.position ?? Duration.zero;
  Timer? _progressTimer;
  Timer? _autoBookmarkTimer;
  String? _activeSessionId;
  Stopwatch? _sessionClock;
  DateTime? _pausedAt;
  static const smartRewindThreshold = Duration(seconds: 60);
  static const smartRewindAmount = Duration(seconds: 5);
  final _stateCtrl = StreamController<m.PlaybackState>.broadcast();
  m.PlaybackState _state = const m.PlaybackState();
  Stream<m.PlaybackState> get stateStream => _stateCtrl.stream;
  m.PlaybackState get state => _state;
  Duration _sleepRemaining = Duration.zero;
  Timer? _sleepTimer;
  bool _sleepEndOfChapter = false;
  bool _waitingForChapterEnd = false;
  int? _sleepChapterEndMs;
  Duration get sleepRemaining => _sleepRemaining;
  bool get sleepEndOfChapter => _sleepEndOfChapter;
  bool get isWaitingForChapterEnd => _waitingForChapterEnd;

  PlaybackService(
      {required this.db,
      required this.library,
      required this.bookmarks,
      required this.history,
      this.settings,
      AudioPlayer? audioPlayer,
      this._backend,
      DateTime Function()? now})
      : _externalPlayer = audioPlayer,
        now = now ?? DateTime.now;

  Future<void> _command(Future<void> Function() action) {
    if (_disposed) {
      return Future.error(StateError('Playback has been disposed'));
    }
    final next = _commands.then((_) => action());
    _commands = next.catchError((Object e, StackTrace stack) {
      _emit(
          state.copyWith(status: m.PlaybackStatus.error, error: e.toString()));
    });
    return next;
  }

  void _background(Future<void> future) {
    unawaited(future.catchError((Object e, StackTrace stack) {
      if (!_disposed) {
        _emit(state.copyWith(
            status: m.PlaybackStatus.error, error: e.toString()));
      }
    }));
  }

  Future<void> init() => _initializing ??= _init();
  Future<void> _init() async {
    _backend ??= JustAudioBackend(
        _externalPlayer ?? AudioPlayer(handleInterruptions: false));
    _subscriptions.add(_backend!.positions.listen((_) {
      _publishPosition();
      _checkChapterEnd();
    }));
    _subscriptions.add(_backend!.indices.listen((i) {
      if (_loading || i == null || i < 0 || i >= _tracks.length) return;
      _publishPosition();
      _background(_audioHandler?.setCurrentIndex(i) ?? Future.value());
      _checkChapterEnd();
    }));
    _subscriptions.add(_backend!.durations.listen((d) {
      _publishPosition();
      if (!_loading &&
          d != null &&
          d > Duration.zero &&
          _index < _tracks.length) {
        final track = _tracks[_index];
        if (track.durationMs != d.inMilliseconds) {
          _background(_command(() async {
            await library.updateTrackDuration(
                track.bookId, track.trackIndex, d);
            if (_currentBookId == track.bookId) {
              _tracks = await db.tracksFor(track.bookId);
              _chapters = await db.chaptersFor(track.bookId);
              await _syncHandler();
            }
          }));
        }
      }
    }));
    _subscriptions.add(_backend!.states.listen((ps) {
      if (_loading) return;
      _emit(state.copyWith(status: ps.toStatus()));
      final eventBookId = _currentBookId;
      _background(_command(() async {
        if (eventBookId != _currentBookId) return;
        if (_backend!.playing &&
            ps.playing &&
            ps.processingState == ProcessingState.ready) {
          await _startSession();
        } else {
          await _endSession();
          if (ps.processingState == ProcessingState.completed) {
            await _persistProgress();
            await _backend!.pause();
            cancelSleepTimer();
          }
        }
      }));
    }, onError: (Object e) {
      _emit(
          state.copyWith(status: m.PlaybackStatus.error, error: e.toString()));
      _background(_command(_endSession));
    }));
    if (_backend is JustAudioBackend) {
      final session = await AudioSession.instance;
      _audioSession = session;
      await session.configure(const AudioSessionConfiguration.speech());
      _subscriptions.add(session.interruptionEventStream.listen((event) {
        if (event.begin) {
          _wasPlayingBeforeInterruption = _backend!.playing;
          if (_wasPlayingBeforeInterruption) _background(_command(_pause));
        } else {
          if (_wasPlayingBeforeInterruption &&
              event.type != AudioInterruptionType.unknown) {
            _background(play());
          }
          _wasPlayingBeforeInterruption = false;
        }
      }));
      _subscriptions.add(
          session.becomingNoisyEventStream.listen((_) => _background(pause())));
    }
    await _applySettings();
    settings?.addListener(_settingsChanged);
    library.beforeDelete = (id) async {
      if (id == _currentBookId) await unload();
    };
    _progressTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_backend?.playing == true) _background(_command(_persistProgress));
    });
    WidgetsBinding.instance.addObserver(this);
    _observing = true;
  }

  void _settingsChanged() => _background(_command(_applySettings));
  Future<void> _applySettings() async {
    if (settings == null || _backend == null) return;
    final speed = settings!.playbackSpeed;
    if (state.speed != speed) await _endSession();
    await _backend!.setSpeed(speed);
    await _backend!.setVolume(settings!.volume);
    await _backend!.setSkipSilence(settings!.skipSilence);
    _emit(state.copyWith(speed: speed, volume: settings!.volume));
    if (_backend!.playing) await _startSession();
    _startAutoBookmark();
  }

  void attachAudioHandler(CrisperAudioHandler handler) {
    _audioHandler = handler;
    handler.setDelegates(
        onPlay: play,
        onPause: pause,
        onStop: stop,
        onSeek: seek,
        onSkipNext: nextChapter,
        onSkipPrev: previousChapter,
        onSeekIndex: seekTrack,
        onSpeed: setSpeed,
        onForward: skipForward,
        onBackward: skipBack);
  }

  Future<void> _syncHandler() async {
    if (_audioHandler == null || _currentBookId == null) return;
    final book = await db.getBook(_currentBookId!);
    if (book == null) return;
    final art = book.coverPath.isNotEmpty ? Uri.file(book.coverPath) : null;
    await _audioHandler!.setQueueItems(_tracks
        .map((t) => MediaItem(
              id: t.filePath,
              album: book.title,
              title: _tracks.length == 1
                  ? book.title
                  : '${book.title} — Part ${t.trackIndex + 1}',
              artist: book.author,
              artUri: art,
              duration: t.durationMs == null
                  ? null
                  : Duration(milliseconds: t.durationMs!),
            ))
        .toList());
    await _audioHandler!.setCurrentIndex(_index);
  }

  Future<void> restoreLastBook() async {
    if (settings?.resumeOnLaunch != true) return;
    final books = await db.allBooks;
    books.removeWhere((b) => b.lastPlayedAtMs == null);
    books.sort((a, b) => b.lastPlayedAtMs!.compareTo(a.lastPlayedAtMs!));
    if (books.isNotEmpty) await loadBook(books.first.id);
  }

  Future<void> loadBook(String id, {bool autoPlay = false}) =>
      _command(() => _loadBook(id, autoPlay: autoPlay));
  Future<void> _loadBook(String id, {bool autoPlay = false}) async {
    await init();
    final storedBook = await db.getBook(id);
    if (storedBook == null) throw StateError('Book not found');
    final tracks = await library.ensureTracks(storedBook);
    final book = (await db.getBook(id))!;
    if (tracks.isEmpty) throw StateError('Book has no files');
    await _backend!.pause();
    await _persistProgress();
    await _endSession();
    cancelSleepTimer();
    _pausedAt = null;
    _loading = true;
    // Suppress intermediate source/index events while replacing the queue.
    try {
      _currentBookId = null;
      _emit(m.PlaybackState(
          status: m.PlaybackStatus.loading,
          speed: state.speed,
          volume: state.volume));
      var index =
          tracks.indexWhere((t) => t.filePath == book.lastPositionFilePath);
      if (index < 0) index = 0;
      final position = _clamp(Duration(milliseconds: book.lastPositionMs),
          tracks[index].durationMs);
      await _backend!.load(tracks.map((t) => t.filePath).toList(),
          index: index, position: position);
      _tracks = tracks;
      final decodedDuration = _backend!.duration;
      if (decodedDuration != null &&
          decodedDuration > Duration.zero &&
          tracks[index].durationMs != decodedDuration.inMilliseconds) {
        await library.updateTrackDuration(id, index, decodedDuration);
        _tracks = await db.tracksFor(id);
      }
      _chapters = await db.chaptersFor(id);
      _currentBookId = id;
      await _applySettings();
      await _syncHandler();
      _emit(state.copyWith(status: m.PlaybackStatus.paused));
      _publishPosition();
      _startAutoBookmark();
    } catch (e) {
      _tracks = [];
      _chapters = [];
      _currentBookId = null;
      await _backend!.stop();
      await _audioHandler?.setQueueItems([]);
      _emit(
          state.copyWith(status: m.PlaybackStatus.error, error: e.toString()));
      rethrow;
    } finally {
      _loading = false;
    }
    if (autoPlay) await _play();
  }

  Future<void> play() => _command(_play);
  Future<void> _play() async {
    final pausedAt = _pausedAt;
    _pausedAt = null;
    if (_currentBookId == null || _backend == null) return;
    if (pausedAt != null && shouldSmartRewind(pausedAt)) {
      await _seekBook(bookPosition - smartRewindAmount);
    }
    if (_audioSession != null && !await _audioSession!.setActive(true)) {
      throw StateError('Audio session unavailable');
    }
    // just_audio's play Future lasts until pause/stop/completion.
    _background(_backend!.play().catchError((Object e) async {
      await _command(() async {
        await _endSession();
        await _persistProgress();
        _emit(state.copyWith(
            status: m.PlaybackStatus.error, error: e.toString()));
      });
    }));
  }

  Future<void> pause() {
    _wasPlayingBeforeInterruption = false;
    return _command(_pause);
  }

  Future<void> _pause() async {
    _pausedAt = now();
    await _backend?.pause();
    await _persistProgress();
    await _maybeAutoBookmark();
    await _endSession();
    _emit(state.copyWith(status: m.PlaybackStatus.paused));
  }

  Future<void> stop() => _command(() async {
        await _pause();
        await _backend?.stop();
        cancelSleepTimer();
        await _audioSession?.setActive(false);
        _emit(state.copyWith(status: m.PlaybackStatus.idle));
      });
  Future<void> unload() => _command(() async {
        await _pause();
        await _backend?.stop();
        _currentBookId = null;
        _tracks = [];
        _chapters = [];
        cancelSleepTimer();
        _autoBookmarkTimer?.cancel();
        await _audioHandler?.setQueueItems([]);
        _emit(m.PlaybackState(speed: state.speed, volume: state.volume));
      });

  Duration _clamp(Duration pos, int? durationMs) {
    if (pos < Duration.zero) return Duration.zero;
    if (durationMs != null && pos.inMilliseconds > durationMs) {
      return Duration(milliseconds: durationMs);
    }
    return pos;
  }

  Duration get bookPosition {
    if (_currentBookId == null || _tracks.isEmpty) return Duration.zero;
    var offset = Duration.zero;
    for (final track in _tracks.take(_index)) {
      if (track.durationMs == null) return offset + _position;
      offset += Duration(milliseconds: track.durationMs!);
    }
    return offset + _position;
  }

  Duration? get bookDuration =>
      _tracks.isEmpty || _tracks.any((t) => t.durationMs == null)
          ? null
          : Duration(
              milliseconds: _tracks.fold(0, (sum, t) => sum + t.durationMs!));

  Future<void> seek(Duration pos) => _command(() async {
        if (_tracks.isEmpty) return;
        await _backend!.seek(_clamp(pos, _tracks[_index].durationMs));
        _publishPosition();
        await _persistProgress();
      });
  Future<void> seekTrack(int index, [Duration position = Duration.zero]) =>
      _command(() => _seekTrack(index, position));
  Future<void> _seekTrack(int index, Duration position) async {
    if (index < 0 || index >= _tracks.length) {
      throw RangeError.index(index, _tracks);
    }
    await _backend!
        .seek(_clamp(position, _tracks[index].durationMs), index: index);
    _publishPosition();
    await _persistProgress();
  }

  Future<void> seekBook(Duration position) =>
      _command(() => _seekBook(position));
  Future<void> _seekBook(Duration position) async {
    if (_tracks.isEmpty) return;
    if (position < Duration.zero) position = Duration.zero;
    var offset = Duration.zero;
    for (var i = 0; i < _tracks.length; i++) {
      final duration = _tracks[i].durationMs;
      if (duration == null) {
        if (position == offset) return _seekTrack(i, Duration.zero);
        throw StateError('Track duration is unknown; select a track directly');
      }
      final end = offset + Duration(milliseconds: duration);
      if (position < end || i == _tracks.length - 1) {
        return _seekTrack(i, position - offset);
      }
      offset = end;
    }
  }

  Future<void> seekChapter(Chapter chapter) =>
      _command(() => _seekChapter(chapter));
  Future<void> _seekChapter(Chapter chapter) async {
    if (_currentBookId != chapter.bookId) await _loadBook(chapter.bookId);
    var index = _tracks.indexWhere((t) => t.filePath == chapter.filePath);
    if (index < 0) index = chapter.trackIndex;
    if (index < 0 || index >= _tracks.length) {
      throw StateError('Chapter file is unavailable');
    }
    final preceding = _tracks.take(index);
    final offset = preceding.fold<int>(
      0,
      (sum, t) => sum + (t.durationMs ?? 0),
    );
    // A physical-file chapter always starts at zero, including unknown timing.
    final onePerFile = _tracks.length > 1 &&
        _chapters.where((c) => c.filePath == chapter.filePath).length == 1;
    await _seekTrack(
      index,
      onePerFile
          ? Duration.zero
          : Duration(milliseconds: chapter.startMs - offset),
    );
  }

  Future<bool> refreshChapters(String bookId) async {
    var refreshed = false;
    await _command(() async {
      refreshed = await library.refreshChapters(bookId);
      if (refreshed && _currentBookId == bookId) {
        _chapters = await db.chaptersFor(bookId);
        _publishPosition();
      }
    });
    return refreshed;
  }

  int get _chapterIndex {
    if (_chapters.isEmpty) return -1;
    final position = bookPosition.inMilliseconds;
    for (var i = _chapters.length - 1; i >= 0; i--) {
      final chapter = _chapters[i];
      if (chapter.trackIndex <= _index && chapter.startMs <= position) return i;
    }
    return 0;
  }

  Future<void> nextChapter() => _command(() async {
        if (_chapters.isEmpty) {
          if (_index + 1 < _tracks.length) {
            await _seekTrack(_index + 1, Duration.zero);
          }
          return;
        }
        final next = _chapterIndex + 1;
        if (next < _chapters.length) await _seekChapter(_chapters[next]);
      });

  /// Restart the current chapter after three seconds; otherwise go back one.
  Future<void> previousChapter() => _command(() async {
        if (_chapters.isEmpty) {
          if (_index > 0) await _seekTrack(_index - 1, Duration.zero);
          return;
        }
        var index = _chapterIndex;
        if (bookPosition.inMilliseconds - _chapters[index].startMs <= 3000 &&
            index > 0) {
          index--;
        }
        await _seekChapter(_chapters[index]);
      });

  Future<void> seekBookmark(Bookmark bookmark) => _command(() async {
        if (_currentBookId != bookmark.bookId) await _loadBook(bookmark.bookId);
        final index =
            _tracks.indexWhere((t) => t.filePath == bookmark.filePath);
        if (index < 0) {
          throw StateError('Bookmark file is missing from this book');
        }
        await _seekTrack(index, Duration(milliseconds: bookmark.positionMs));
      });
  int get seekSeconds => settings?.seekSeconds ?? 30;
  Future<void> skipForward([int? seconds]) => _skip(seconds ?? seekSeconds);
  Future<void> skipBack([int? seconds]) => _skip(-(seconds ?? seekSeconds));
  Future<void> _skip(int seconds) => _command(() async {
        if (_tracks.isEmpty) return;
        final delta = Duration(seconds: seconds);
        if (bookDuration == null) {
          await _seekTrack(_index, _position + delta);
        } else {
          await _seekBook(bookPosition + delta);
        }
      });
  Future<void> nextTrack() => _command(() async {
        if (_index + 1 < _tracks.length) {
          await _seekTrack(_index + 1, Duration.zero);
        }
      });
  Future<void> previousTrack() => _command(() async {
        if (_index > 0) await _seekTrack(_index - 1, Duration.zero);
      });
  Future<void> setSpeed(double speed) => _command(() async {
        speed = speed.clamp(0.5, 3.0);
        await _endSession();
        await _backend?.setSpeed(speed);
        _emit(state.copyWith(speed: speed));
        settings?.playbackSpeed = speed;
        if (_backend?.playing == true) await _startSession();
      });
  Future<void> setVolume(double volume) => _command(() async {
        volume = volume.clamp(0.0, 1.0);
        await _backend?.setVolume(volume);
        _emit(state.copyWith(volume: volume));
        settings?.volume = volume;
      });

  void setSleepTimer(Duration duration, {bool endOfChapter = false}) {
    cancelSleepTimer();
    _sleepRemaining = duration < Duration.zero ? Duration.zero : duration;
    _sleepEndOfChapter = endOfChapter;
    if (_sleepRemaining == Duration.zero) {
      if (endOfChapter) _armChapterEnd();
    } else {
      _sleepTimer =
          Timer.periodic(const Duration(seconds: 1), (_) => _tickSleep());
    }
    _emit(state);
  }

  void _tickSleep() {
    _sleepRemaining -= const Duration(seconds: 1);
    if (_sleepRemaining <= Duration.zero) {
      _sleepRemaining = Duration.zero;
      _sleepTimer?.cancel();
      _sleepTimer = null;
      if (_sleepEndOfChapter) {
        _armChapterEnd();
      } else {
        _background(pause());
      }
    }
    _emit(state);
  }

  void _armChapterEnd() {
    final pos = bookPosition.inMilliseconds;
    _sleepChapterEndMs = null;
    for (final chapter in _chapters) {
      if (chapter.startMs <= pos && pos < chapter.endMs) {
        _sleepChapterEndMs = chapter.endMs;
        break;
      }
    }
    _waitingForChapterEnd = true;
    // Fall back to the end of this physical track if chapter metadata is absent.
    _sleepChapterEndMs ??= _tracks.isEmpty || _tracks[_index].durationMs == null
        ? null
        : (bookPosition - _position).inMilliseconds +
            _tracks[_index].durationMs!;
    if (_sleepChapterEndMs == null && _currentBookId != null) {
      cancelSleepTimer();
      _background(pause());
    }
  }

  void _checkChapterEnd() {
    if (!_waitingForChapterEnd || _sleepChapterEndMs == null) return;
    if (bookPosition.inMilliseconds >= _sleepChapterEndMs!) {
      cancelSleepTimer();
      _background(pause());
    }
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepRemaining = Duration.zero;
    _sleepEndOfChapter = false;
    _waitingForChapterEnd = false;
    _sleepChapterEndMs = null;
    _emit(state);
  }

  Future<String> addManualBookmark({String? title, String? note}) async {
    await _commands;
    if (_currentBookId == null || _tracks.isEmpty) {
      throw StateError('No book loaded');
    }
    return bookmarks.addManual(
        bookId: _currentBookId!,
        filePath: _tracks[_index].filePath,
        position: _position,
        bookPosition: bookPosition,
        title: title,
        note: note);
  }

  void _publishPosition() {
    if (_loading || _tracks.isEmpty || _index >= _tracks.length) return;
    _emit(state.copyWith(
        position: _position,
        duration: _backend?.duration ??
            Duration(milliseconds: _tracks[_index].durationMs ?? 0),
        currentIndex: _index,
        currentFile: _tracks[_index].filePath));
  }

  void _emit(m.PlaybackState next) {
    _state = next;
    if (!_stateCtrl.isClosed) _stateCtrl.add(next);
  }

  Future<void> _persistProgress() async {
    if (_currentBookId == null || _tracks.isEmpty || _index >= _tracks.length) {
      return;
    }
    await library.updateProgress(_currentBookId!, _tracks[_index].filePath,
        _position, bookPosition, bookDuration ?? Duration.zero);
    if (_activeSessionId != null) {
      await history.endSession(
          _activeSessionId!, bookPosition, _sessionClock!.elapsed,
          close: false);
    }
  }

  void _startAutoBookmark() {
    _autoBookmarkTimer?.cancel();
    if (_currentBookId == null || settings?.autoBookmarkEnabled == false) {
      return;
    }
    _autoBookmarkTimer = Timer.periodic(
        settings?.autoBookmarkInterval ?? const Duration(minutes: 5), (_) {
      if (_backend?.playing == true) _background(_command(_maybeAutoBookmark));
    });
  }

  Future<void> _maybeAutoBookmark() async {
    if (settings?.autoBookmarkEnabled == false ||
        _currentBookId == null ||
        _tracks.isEmpty ||
        _position == Duration.zero) {
      return;
    }
    await bookmarks.addAuto(
        bookId: _currentBookId!,
        filePath: _tracks[_index].filePath,
        position: _position,
        bookPosition: bookPosition);
    await bookmarks.pruneAuto(_currentBookId!);
  }

  Future<void> _startSession() async {
    if (_activeSessionId != null || _currentBookId == null) return;
    _sessionClock = Stopwatch()..start();
    _activeSessionId = await history.startSession(
        bookId: _currentBookId!, startPos: bookPosition, speed: state.speed);
  }

  Future<void> _endSession() async {
    if (_activeSessionId == null) return;
    final id = _activeSessionId!;
    final elapsed = _sessionClock!.elapsed;
    _sessionClock!.stop();
    _activeSessionId = null;
    _sessionClock = null;
    await history.endSession(id, bookPosition, elapsed);
  }

  bool shouldSmartRewind(DateTime pausedAt, {DateTime? now}) =>
      (now ?? this.now()).difference(pausedAt) > smartRewindThreshold;
  Duration applySmartRewind(Duration pos) =>
      pos < smartRewindAmount ? Duration.zero : pos - smartRewindAmount;

  /// Flush position on backgrounding; the listening session continues with audio.
  Future<void> handleAppPaused() => _command(_persistProgress);
  Future<void> handleAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.paused) await handleAppPaused();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _background(handleAppPaused());
  }

  Future<void> dispose() async {
    if (_disposed) return;
    settings?.removeListener(_settingsChanged);
    library.beforeDelete = null;
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    _progressTimer?.cancel();
    _autoBookmarkTimer?.cancel();
    _sleepTimer?.cancel();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _commands;
    if (_currentBookId != null) {
      await _backend?.pause();
      await _persistProgress();
      await _endSession();
    }
    _disposed = true;
    await _backend?.dispose();
    await _audioHandler?.dispose();
    await _stateCtrl.close();
  }
}
