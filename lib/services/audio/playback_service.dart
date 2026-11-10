import 'dart:async';
import 'package:drift/drift.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:uuid/uuid.dart';
import '../../models/playback_state.dart' as m;
import '../../models/return_trail.dart';
import '../../models/listening_coverage.dart';
import '../db/app_database.dart';
import '../history_service.dart';
import '../library_service.dart';
import '../bookmark_service.dart';
import '../settings_service.dart';
import '../return_trail_service.dart';
import '../listening_coverage_service.dart';
import '../listening_journal_service.dart';
import '../../models/listening_journal.dart';
import 'audio_backend.dart';
import 'android_audio_effects.dart';
import 'audio_handler.dart';
import 'played_range_recorder.dart';
import 'listening_journal_recorder.dart';
import 'speed_processing.dart';

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
  bool _seeking = false;
  bool _backendReady = false;
  int? _capturedTrackIndex;
  final _playedRanges = PlayedRangeRecorder();
  final _journalSamples = PlayedRangeRecorder(retainPending: false);
  final _journalPassages = ListeningJournalRecorder();
  final List<_JournalEvent> _journalEvents = [];
  bool _journalEnabled = false;
  bool _journalClearing = false;
  int? _journalTrackIndex;
  int? _journalUtcOffsetMinutes;
  ReturnTrailPlan? _returnTrailPlan;
  ReturnTrailPlan? get returnTrailPlan => _returnTrailPlan;
  bool get isReturnTrailActive => _returnTrailPlan != null;
  int _returnTrailClipIndex = 0;
  int get returnTrailClipIndex => _returnTrailClipIndex;
  int _trailGeneration = 0;
  bool _trailTransitioning = false;
  bool _trailAdvancePending = false;
  bool _trailResumeRequested = false;
  Timer? _returnTrailTimer;
  bool _wasPlayingBeforeInterruption = false;
  bool _observing = false;
  String? _currentBookId;
  String? get currentBookId => _currentBookId;
  List<BookTrack> _tracks = [];
  List<Chapter> _chapters = [];
  Map<String, dynamic> _bookPreferences = {};
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
  DateTime? _sleepDeadline;
  Timer? _sleepTimer;
  bool _sleepEndOfChapter = false;
  bool _waitingForChapterEnd = false;
  int? _sleepChapterEndMs;
  Duration get sleepRemaining {
    final remaining = _sleepDeadline?.difference(now()) ?? Duration.zero;
    return remaining < Duration.zero ? Duration.zero : remaining;
  }

  bool get sleepEndOfChapter => _sleepEndOfChapter;
  bool get isWaitingForChapterEnd => _waitingForChapterEnd;

  PlaybackService({
    required this.db,
    required this.library,
    required this.bookmarks,
    required this.history,
    this.settings,
    AudioPlayer? audioPlayer,
    this._backend,
    DateTime Function()? now,
  }) : _externalPlayer = audioPlayer,
       now = now ?? DateTime.now;

  Future<void> _command(Future<void> Function() action) {
    if (_disposed) {
      return Future.error(StateError('Playback has been disposed'));
    }
    final next = _commands.then((_) => action());
    _commands = next.catchError((Object e, StackTrace stack) {
      _emit(
        state.copyWith(status: m.PlaybackStatus.error, error: e.toString()),
      );
    });
    return next;
  }

  void _background(Future<void> future) {
    unawaited(
      future.catchError((Object e, StackTrace stack) {
        if (!_disposed) {
          _emit(
            state.copyWith(status: m.PlaybackStatus.error, error: e.toString()),
          );
        }
      }),
    );
  }

  Future<void> init() => _initializing ??= _init();
  Future<void> _init() async {
    _backend ??= JustAudioBackend(
      _externalPlayer ??
          AudioPlayer(
            handleInterruptions: false,
            audioLoadConfiguration: SpeedProcessing.audioLoadConfiguration,
          ),
    );
    _subscriptions.add(
      _backend!.positions.listen((_) {
        _capturePlayedPosition();
        _publishPosition();
        _checkReturnTrailEnd();
        _checkChapterEnd();
      }),
    );
    _subscriptions.add(
      _backend!.indices.listen((i) {
        if (_loading || i == null || i < 0 || i >= _tracks.length) return;
        _captureNaturalTrackEnd(i);
        _publishPosition();
        _background(_audioHandler?.setCurrentIndex(i) ?? Future.value());
        _checkChapterEnd();
        _checkReturnTrailEnd();
      }),
    );
    _subscriptions.add(
      _backend!.durations.listen((d) {
        _publishPosition();
        if (!_loading &&
            d != null &&
            d > Duration.zero &&
            _index < _tracks.length) {
          final track = _tracks[_index];
          if (track.durationMs != d.inMilliseconds) {
            _background(
              _command(() async {
                await library.updateTrackDuration(
                  track.bookId,
                  track.trackIndex,
                  d,
                );
                if (_currentBookId == track.bookId) {
                  _tracks = await db.tracksFor(track.bookId);
                  _chapters = await db.chaptersFor(track.bookId);
                  await _syncHandler();
                }
              }),
            );
          }
        }
      }),
    );
    _subscriptions.add(
      _backend!.states.listen(
        (ps) {
          if (_loading) return;
          if (ps.processingState == ProcessingState.completed) {
            _capturePlayedPosition(completed: true);
            if (state.status != m.PlaybackStatus.completed &&
                !_trailTransitioning) {
              _recordJournalEvent('complete');
            }
          }
          _backendReady = ps.processingState == ProcessingState.ready;
          if (ps.playing && _backendReady) {
            if (!state.isPlaying && !_seeking && !_trailTransitioning) {
              _recordJournalEvent('play');
            }
            _capturePlayedPosition();
          } else {
            _resetPlayedCapture();
            _returnTrailTimer?.cancel();
          }
          _emit(state.copyWith(status: ps.toStatus()));
          final eventBookId = _currentBookId;
          final eventTrail = _returnTrailPlan;
          final eventGeneration = _trailGeneration;
          final eventTrailTransitioning = _trailTransitioning;
          _background(
            _command(() async {
              if (eventBookId != _currentBookId) return;
              // Events emitted by an old excerpt must never complete a book
              // after a return action has restored ordinary playback.
              if (eventTrail != null || isReturnTrailActive) {
                if (eventTrail == _returnTrailPlan &&
                    eventGeneration == _trailGeneration &&
                    isReturnTrailActive) {
                  if (ps.processingState == ProcessingState.completed) {
                    if (_trailResumeRequested && !eventTrailTransitioning) {
                      await _advanceReturnTrail();
                    }
                  } else if (ps.playing && _backendReady) {
                    _scheduleReturnTrailEnd();
                  }
                }
                return;
              }
              if (_backend!.playing &&
                  ps.playing &&
                  ps.processingState == ProcessingState.ready) {
                await _startSession();
              } else {
                await _endSession();
                if (ps.processingState == ProcessingState.completed) {
                  await _persistProgress();
                  final allowNext =
                      ps.playing &&
                      _sleepTimer == null &&
                      !_waitingForChapterEnd;
                  await _backend!.pause();
                  cancelSleepTimer();
                  if (allowNext) await _playNextQueued();
                }
              }
            }),
          );
        },
        onError: (Object e) {
          _recordJournalEvent('interruption', reason: 'decoder_error');
          _backendReady = false;
          _resetPlayedCapture();
          _returnTrailTimer?.cancel();
          _trailResumeRequested = false;
          _emit(
            state.copyWith(status: m.PlaybackStatus.error, error: e.toString()),
          );
          _background(_command(_endSession));
        },
      ),
    );
    if (_backend is JustAudioBackend) {
      final session = await AudioSession.instance;
      _audioSession = session;
      await session.configure(const AudioSessionConfiguration.speech());
      _subscriptions.add(
        session.interruptionEventStream.listen((event) {
          if (event.begin) {
            _wasPlayingBeforeInterruption = _backend!.playing;
            _trailResumeRequested = false;
            _returnTrailTimer?.cancel();
            if (_wasPlayingBeforeInterruption) {
              _background(
                _command(
                  () => _pause(
                    journalKind: 'interruption',
                    reason: 'audio_interruption',
                  ),
                ),
              );
            }
          } else {
            if (_wasPlayingBeforeInterruption &&
                event.type != AudioInterruptionType.unknown) {
              _background(play());
            }
            _wasPlayingBeforeInterruption = false;
          }
        }),
      );
      _subscriptions.add(
        session.becomingNoisyEventStream.listen((_) {
          _wasPlayingBeforeInterruption = false;
          _trailResumeRequested = false;
          _returnTrailTimer?.cancel();
          _background(
            _command(
              () => _pause(
                journalKind: 'interruption',
                reason: 'audio_output_changed',
              ),
            ),
          );
        }),
      );
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

  void _settingsChanged() {
    // Apply consent at the notification boundary, before queued audio work.
    _syncJournalPreference();
    _background(_command(_applySettings));
  }

  Future<void> _applySettings() async {
    if (settings == null || _backend == null) return;
    _syncJournalPreference();
    final speed =
        (_bookPreferences['speed'] as num?)?.toDouble() ??
        settings!.playbackSpeed;
    if (state.speed != speed) {
      _capturePlayedPosition();
      _resetPlayedCapture();
      await _endSession();
    }
    await _backend!.setSpeed(speed);
    await _backend!.setVolume(settings!.volume);
    await _backend!.setSkipSilence(
      _bookPreferences['skipSilence'] as bool? ?? settings!.skipSilence,
    );
    if (_backend is AudioEffectsBackend) {
      await (_backend as AudioEffectsBackend).setAudioEffects(
        boostDb:
            (_bookPreferences['boostDb'] as num?)?.toDouble() ??
            settings!.boostDb,
        equalizer:
            _bookPreferences['equalizer'] as String? ?? settings!.equalizer,
      );
    }
    _emit(state.copyWith(speed: speed, volume: settings!.volume));
    if (_backend!.playing) await _startSession();
    _capturePlayedPosition();
    _scheduleReturnTrailEnd();
    _startAutoBookmark();
  }

  bool get supportsSkipSilence => _backend?.supportsSkipSilence ?? false;

  bool get supportsAudioEffects =>
      _backend is AudioEffectsBackend &&
      (_backend as AudioEffectsBackend).supportsAudioEffects;
  String? get audioEffectsError => _backend is AudioEffectsBackend
      ? (_backend as AudioEffectsBackend).audioEffectsError
      : null;

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
      onBackward: skipBack,
    );
  }

  Future<void> _syncHandler() async {
    if (_audioHandler == null || _currentBookId == null) return;
    final book = await db.getBook(_currentBookId!);
    if (book == null) return;
    final art = book.coverPath.isNotEmpty ? Uri.file(book.coverPath) : null;
    await _audioHandler!.setQueueItems(
      _tracks
          .map(
            (t) => MediaItem(
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
            ),
          )
          .toList(),
    );
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
    if (isReturnTrailActive) await _finishReturnTrail();
    _capturePlayedPosition();
    _recordJournalEvent('close', reason: 'book_changed');
    await _backend!.pause();
    await _persistProgress();
    await _endSession();
    cancelSleepTimer();
    _pausedAt = null;
    _loading = true;
    _backendReady = false;
    _capturedTrackIndex = null;
    _resetPlayedCapture();
    // Suppress intermediate source/index events while replacing the queue.
    try {
      _currentBookId = null;
      _emit(
        m.PlaybackState(
          status: m.PlaybackStatus.loading,
          speed: state.speed,
          volume: state.volume,
        ),
      );
      var index = tracks.indexWhere(
        (t) => t.filePath == book.lastPositionFilePath,
      );
      if (index < 0) index = 0;
      final position = _clamp(
        Duration(milliseconds: book.lastPositionMs),
        tracks[index].durationMs,
      );
      await _backend!.load(
        tracks.map((t) => t.filePath).toList(),
        index: index,
        position: position,
      );
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
      _bookPreferences = await library.preferences(id);
      await _applySettings();
      await _syncHandler();
      _emit(state.copyWith(status: m.PlaybackStatus.paused));
      _startAutoBookmark();
    } catch (e) {
      _tracks = [];
      _chapters = [];
      _currentBookId = null;
      await _backend!.stop();
      await _audioHandler?.setQueueItems([]);
      _emit(
        state.copyWith(status: m.PlaybackStatus.error, error: e.toString()),
      );
      rethrow;
    } finally {
      _loading = false;
    }
    // Loading suppresses backend position events; publish the selected track once
    // loading has ended, including for a paused load with no later audio event.
    _publishPosition();
    _recordJournalEvent('open');
    await _flushListeningJournal();
    if (autoPlay) await _play();
  }

  Future<void> play() => _command(_play);
  Future<void> _play() async {
    if (isReturnTrailActive) {
      _trailResumeRequested = true;
      await _playReturnTrailAudio();
      return;
    }
    final pausedAt = _pausedAt;
    _pausedAt = null;
    if (_currentBookId == null || _backend == null) return;
    if (bookDuration != null && bookPosition >= bookDuration!) {
      await _seekBook(Duration.zero, journalReason: 'restart');
    }
    if (pausedAt != null && shouldSmartRewind(pausedAt)) {
      await _seekBook(
        applySmartRewind(bookPosition),
        journalReason: 'smart_rewind',
      );
    }
    if (_audioSession != null && !await _audioSession!.setActive(true)) {
      throw StateError('Audio session unavailable');
    }
    await (db.update(db.books)..where((t) => t.id.equals(_currentBookId!)))
        .write(const BooksCompanion(finishedOverride: Value(null)));
    // just_audio's play Future lasts until pause/stop/completion.
    _background(
      _backend!.play().catchError((Object e) async {
        await _command(() async {
          await _endSession();
          await _persistProgress();
          _emit(
            state.copyWith(status: m.PlaybackStatus.error, error: e.toString()),
          );
        });
      }),
    );
  }

  Future<void> pause() {
    _wasPlayingBeforeInterruption = false;
    _trailResumeRequested = false;
    _returnTrailTimer?.cancel();
    return _command(_pause);
  }

  Future<void> _pause({
    String journalKind = 'pause',
    String? reason,
    bool recordWhilePaused = false,
  }) async {
    _trailResumeRequested = false;
    _returnTrailTimer?.cancel();
    _capturePlayedPosition();
    if (_backend?.playing == true || recordWhilePaused) {
      _recordJournalEvent(journalKind, reason: reason);
    }
    _resetPlayedCapture();
    _pausedAt = now();
    await _backend?.pause();
    await _persistProgress();
    await _maybeAutoBookmark();
    await _endSession();
    _emit(state.copyWith(status: m.PlaybackStatus.paused));
  }

  Future<void> stop() => _command(() async {
    if (isReturnTrailActive) await _finishReturnTrail();
    await _pause(journalKind: 'stop', recordWhilePaused: true);
    await _backend?.stop();
    cancelSleepTimer();
    await _audioSession?.setActive(false);
    _emit(state.copyWith(status: m.PlaybackStatus.idle));
  });
  Future<void> unload() => _command(() async {
    if (isReturnTrailActive) await _finishReturnTrail();
    await _pause(journalKind: 'close', recordWhilePaused: true);
    await _backend?.stop();
    _currentBookId = null;
    _tracks = [];
    _capturedTrackIndex = null;
    _chapters = [];
    _bookPreferences = {};
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
          milliseconds: _tracks.fold(0, (sum, t) => sum + t.durationMs!),
        );

  Future<void> seek(Duration pos) => _command(() async {
    if (_tracks.isEmpty) return;
    await _seekTrack(_index, pos);
  });
  Future<void> seekTrack(int index, [Duration position = Duration.zero]) =>
      _command(() => _seekTrack(index, position));
  Future<void> _seekTrack(
    int index,
    Duration position, {
    String journalReason = 'seek',
  }) async {
    if (index < 0 || index >= _tracks.length) {
      throw RangeError.index(index, _tracks);
    }
    if (isReturnTrailActive) {
      final clip = _returnTrailPlan!.clips[_returnTrailClipIndex];
      // Ordinary scrubbing remains inside the reviewed passage. The dedicated
      // Continue action is the only way to adopt a new permanent place.
      await _seekReturnTrailClip(
        _returnTrailClipIndex,
        position: index == clip.trackIndex ? position : null,
        play: _trailResumeRequested && _backend!.playing,
      );
      return;
    }
    _capturePlayedPosition();
    final from = _journalAnchor();
    _resetPlayedCapture();
    _seeking = true;
    try {
      await _backend!.seek(
        _clamp(position, _tracks[index].durationMs),
        index: index,
      );
    } finally {
      _seeking = false;
      _resetPlayedCapture();
    }
    _capturePlayedPosition();
    _publishPosition();
    if (from != null &&
        (from.filePath != _tracks[_index].filePath ||
            from.positionMs != _position.inMilliseconds)) {
      _recordJournalEvent(
        'seek',
        anchor: from,
        targetFilePath: _tracks[_index].filePath,
        targetPositionMs: _position.inMilliseconds,
        reason: journalReason,
      );
    }
    await _persistProgress();
  }

  Future<void> seekBook(Duration position) =>
      _command(() => _seekBook(position));
  Future<void> _seekBook(
    Duration position, {
    String journalReason = 'seek',
  }) async {
    if (_tracks.isEmpty) return;
    if (position < Duration.zero) position = Duration.zero;
    var offset = Duration.zero;
    for (var i = 0; i < _tracks.length; i++) {
      final duration = _tracks[i].durationMs;
      if (duration == null) {
        if (position == offset) {
          return _seekTrack(i, Duration.zero, journalReason: journalReason);
        }
        throw StateError('Track duration is unknown; select a track directly');
      }
      final end = offset + Duration(milliseconds: duration);
      if (position < end || i == _tracks.length - 1) {
        return _seekTrack(i, position - offset, journalReason: journalReason);
      }
      offset = end;
    }
  }

  Future<void> seekChapter(Chapter chapter) =>
      _command(() => _seekChapter(chapter));
  Future<void> _seekChapter(
    Chapter chapter, {
    String journalReason = 'chapter',
  }) async {
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
    final onePerFile =
        _tracks.length > 1 &&
        _chapters.where((c) => c.filePath == chapter.filePath).length == 1;
    await _seekTrack(
      index,
      onePerFile
          ? Duration.zero
          : Duration(milliseconds: chapter.startMs - offset),
      journalReason: journalReason,
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
    if (isReturnTrailActive) return _advanceReturnTrail();
    if (_chapters.isEmpty) {
      if (_index + 1 < _tracks.length) {
        await _seekTrack(
          _index + 1,
          Duration.zero,
          journalReason: 'next_chapter',
        );
      }
      return;
    }
    final next = _chapterIndex + 1;
    if (next < _chapters.length) {
      await _seekChapter(_chapters[next], journalReason: 'next_chapter');
    }
  });

  /// Restart the current chapter after three seconds; otherwise go back one.
  Future<void> previousChapter() => _command(() async {
    if (isReturnTrailActive) {
      return _seekReturnTrailClip(
        (_returnTrailClipIndex - 1).clamp(
          0,
          _returnTrailPlan!.clips.length - 1,
        ),
        play: _trailResumeRequested && _backend!.playing,
      );
    }
    if (_chapters.isEmpty) {
      if (_index > 0) {
        await _seekTrack(
          _index - 1,
          Duration.zero,
          journalReason: 'previous_chapter',
        );
      }
      return;
    }
    var index = _chapterIndex;
    if (bookPosition.inMilliseconds - _chapters[index].startMs <= 3000 &&
        index > 0) {
      index--;
    }
    await _seekChapter(_chapters[index], journalReason: 'previous_chapter');
  });

  Future<void> updateBookPreferences(
    String id,
    Map<String, dynamic> values, {
    bool reset = false,
  }) => _command(() async {
    await library.setPreferences(id, values, reset: reset);
    if (id == _currentBookId) {
      _bookPreferences = await library.preferences(id);
      await _applySettings();
    }
  });

  Future<void> updateBookDetails(String id, Map<String, dynamic> values) =>
      _command(() async {
        await library.editBook(id, values);
        if (id == _currentBookId) await _syncHandler();
      });

  Future<void> markBook(String id, String status) => _command(() async {
    if (!{'finished', 'unfinished', 'unread'}.contains(status)) {
      throw const FormatException('Invalid reading status');
    }
    if (await db.getBook(id) == null) throw StateError('Book not found');
    if (id == _currentBookId) {
      if (isReturnTrailActive) await _finishReturnTrail();
      await _pause();
      cancelSleepTimer();
      if (status == 'unread' && _tracks.isNotEmpty) {
        await _seekTrack(0, Duration.zero, journalReason: 'mark_unread');
      }
    }
    final stored = (await db.getBook(id))!;
    final tracks = await db.tracksFor(id);
    var position = stored.lastPositionMs;
    final index = tracks.indexWhere(
      (t) => t.filePath == stored.lastPositionFilePath,
    );
    for (var i = 0; i < index; i++) {
      position += tracks[i].durationMs ?? 0;
    }
    final progress = stored.totalDurationMs > 0
        ? (position / stored.totalDurationMs).clamp(0.0, 1.0)
        : 0.0;
    await (db.update(db.books)..where((t) => t.id.equals(id))).write(
      BooksCompanion(
        isFinished: Value(status == 'finished'),
        finishedOverride: Value(status == 'finished'),
        totalProgress: Value(
          status == 'finished'
              ? 1
              : status == 'unread'
              ? 0
              : progress,
        ),
        lastPositionMs: status == 'unread'
            ? const Value(0)
            : const Value.absent(),
        lastPositionFilePath: status == 'unread'
            ? const Value(null)
            : const Value.absent(),
        lastPlayedAtMs: status == 'unread'
            ? const Value(null)
            : const Value.absent(),
      ),
    );
  });

  Future<void> enqueue(String id, {int? position}) => _command(
    () => db.transaction(() async {
      if (await db.getBook(id) == null) throw StateError('Book not found');
      final ids = (await db.queue())
          .map((e) => e.bookId)
          .where((e) => e != id)
          .toList();
      ids.insert((position ?? ids.length).clamp(0, ids.length), id);
      await db.replaceQueue(ids);
    }),
  );
  Future<void> removeFromQueue(String id) => _command(() async {
    await (db.delete(db.playbackQueue)..where((t) => t.bookId.equals(id))).go();
  });
  Future<void> playNextQueued() => _command(_playNextQueued);
  Future<void> _playNextQueued() async {
    final entries = await db.queue();
    if (entries.isEmpty) return;
    final id = entries.first.bookId;
    // Keep the entry if loading fails, so a missing file never loses the queue.
    await _loadBook(id, autoPlay: true);
    await (db.delete(db.playbackQueue)..where((t) => t.bookId.equals(id))).go();
  }

  Future<void> seekBookmark(Bookmark bookmark) => _command(() async {
    if (isReturnTrailActive) await _finishReturnTrail();
    if (_currentBookId != bookmark.bookId) await _loadBook(bookmark.bookId);
    final index = _tracks.indexWhere((t) => t.filePath == bookmark.filePath);
    if (index < 0) {
      throw StateError('Bookmark file is missing from this book');
    }
    await _seekTrack(
      index,
      Duration(milliseconds: bookmark.positionMs),
      journalReason: 'bookmark',
    );
  });
  int get seekSeconds =>
      _bookPreferences['seekSeconds'] as int? ?? settings?.seekSeconds ?? 30;
  Future<void> skipForward([int? seconds]) => _skip(seconds ?? seekSeconds);
  Future<void> skipBack([int? seconds]) => _skip(-(seconds ?? seekSeconds));
  Future<void> _skip(int seconds) => _command(() async {
    if (_tracks.isEmpty) return;
    final delta = Duration(seconds: seconds);
    if (isReturnTrailActive) {
      await _seekTrack(
        _index,
        _position + delta,
        journalReason: seconds >= 0 ? 'skip_forward' : 'skip_back',
      );
      return;
    }
    if (bookDuration == null) {
      await _seekTrack(
        _index,
        _position + delta,
        journalReason: seconds >= 0 ? 'skip_forward' : 'skip_back',
      );
    } else {
      await _seekBook(
        bookPosition + delta,
        journalReason: seconds >= 0 ? 'skip_forward' : 'skip_back',
      );
    }
  });
  Future<void> nextTrack() => _command(() async {
    if (isReturnTrailActive) return _advanceReturnTrail();
    if (_index + 1 < _tracks.length) {
      await _seekTrack(_index + 1, Duration.zero, journalReason: 'next_track');
    }
  });
  Future<void> previousTrack() => _command(() async {
    if (isReturnTrailActive) {
      return _seekReturnTrailClip(
        (_returnTrailClipIndex - 1).clamp(
          0,
          _returnTrailPlan!.clips.length - 1,
        ),
        play: _trailResumeRequested && _backend!.playing,
      );
    }
    if (_index > 0) {
      await _seekTrack(
        _index - 1,
        Duration.zero,
        journalReason: 'previous_track',
      );
    }
  });
  Future<void> setSpeed(double speed, {String? expectedBookId}) =>
      _command(() async {
        if (expectedBookId != null && expectedBookId != _currentBookId) {
          throw StateError(
            'The playing book changed. Reopen its speed controls.',
          );
        }
        if (!speed.isFinite) throw ArgumentError.value(speed, 'speed');
        _capturePlayedPosition();
        _resetPlayedCapture();
        speed = speed.clamp(0.5, 3.0);
        await _endSession();
        await _backend?.setSpeed(speed);
        _emit(state.copyWith(speed: speed));
        if (_currentBookId != null) {
          await library.setPreferences(_currentBookId!, {'speed': speed});
          _bookPreferences = await library.preferences(_currentBookId!);
        } else {
          settings?.playbackSpeed = speed;
        }
        if (_backend?.playing == true) await _startSession();
        _capturePlayedPosition();
        _scheduleReturnTrailEnd();
      });
  Future<void> setVolume(double volume) => _command(() async {
    volume = volume.clamp(0.0, 1.0);
    await _backend?.setVolume(volume);
    _emit(state.copyWith(volume: volume));
    settings?.volume = volume;
  });

  void setSleepTimer(Duration duration, {bool endOfChapter = false}) {
    cancelSleepTimer();
    duration = duration < Duration.zero ? Duration.zero : duration;
    _sleepEndOfChapter = endOfChapter;
    if (duration == Duration.zero) {
      if (endOfChapter) _armChapterEnd();
    } else {
      _sleepDeadline = now().add(duration);
      _sleepTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _tickSleep(),
      );
    }
    _emit(state);
  }

  void _tickSleep() {
    if (_sleepDeadline == null) return;
    if (sleepRemaining == Duration.zero) {
      _sleepDeadline = null;
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

  void extendSleepTimer(Duration extra) {
    if (extra <= Duration.zero || extra > const Duration(hours: 24)) {
      throw ArgumentError('Extend by more than zero and at most 24 hours.');
    }
    if (_sleepDeadline == null && !_waitingForChapterEnd) {
      throw StateError('No active sleep timer');
    }
    final extended = sleepRemaining + extra;
    setSleepTimer(
      extended > const Duration(hours: 24)
          ? const Duration(hours: 24)
          : extended,
      endOfChapter: _sleepEndOfChapter,
    );
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
    _sleepDeadline = null;
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
      note: note,
    );
  }

  void _syncJournalPreference() {
    final enabled = settings?.listeningJournalEnabled ?? false;
    if (enabled == _journalEnabled) return;
    // End the old consent window at an observed position. Starting a new
    // window always takes a new baseline, including while audio is playing.
    if (_journalEnabled) _captureJournalPosition();
    _resetJournalCapture();
    _journalEnabled = enabled;
    if (enabled) _captureJournalPosition();
  }

  void _resetJournalCapture() {
    _journalSamples.reset();
    _journalPassages.reset();
    _journalTrackIndex = null;
    _journalUtcOffsetMinutes = null;
  }

  String? _journalChapterTitle(int index, int positionMs) {
    if (index < 0 || index >= _tracks.length) return null;
    final track = _tracks[index];
    final candidates = _chapters
        .where(
          (chapter) =>
              chapter.filePath == track.filePath ||
              (chapter.filePath == null &&
                  chapter.trackIndex == track.trackIndex),
        )
        .toList();
    if (candidates.isEmpty) return null;
    if (candidates.length == 1 && _tracks.length > 1) {
      return candidates.single.title;
    }
    if (_tracks.take(index).any((track) => track.durationMs == null)) {
      return null;
    }
    final offset = _tracks
        .take(index)
        .fold<int>(0, (sum, track) => sum + track.durationMs!);
    final position = offset + positionMs;
    return candidates
        .where(
          (chapter) => chapter.startMs <= position && position < chapter.endMs,
        )
        .firstOrNull
        ?.title;
  }

  void _sampleJournal(int index, int positionMs, DateTime observedAt) {
    final offset = observedAt.timeZoneOffset.inMinutes;
    if (_journalUtcOffsetMinutes != offset) {
      // Do not attach a new time-zone offset to an older observation. UTC
      // timestamps remain authoritative; a changed offset starts a new pair.
      _journalSamples.reset();
      _journalPassages.reset();
      _journalUtcOffsetMinutes = offset;
    }
    final track = _tracks[index];
    final range = _journalSamples.sample(
      bookId: _currentBookId!,
      filePath: track.filePath,
      positionMs: positionMs,
      observedAtMs: observedAt.millisecondsSinceEpoch,
      speed: state.speed,
    );
    if (range == null) return;
    _journalPassages.record(
      range,
      speed: state.speed,
      utcOffsetMinutes: offset,
      chapterTitle: _journalChapterTitle(index, range.startMs),
      reason: isReturnTrailActive ? 'return_trail' : null,
    );
  }

  void _captureJournalPosition({bool completed = false}) {
    if (!_journalEnabled ||
        _journalClearing ||
        _loading ||
        _seeking ||
        _trailTransitioning ||
        !_backendReady ||
        (_backend?.playing != true && !(completed && state.isPlaying)) ||
        _currentBookId == null ||
        _index < 0 ||
        _index >= _tracks.length) {
      return;
    }
    final observedAt = now();
    final previous = _journalTrackIndex;
    if (previous != null && previous != _index) {
      if (!isReturnTrailActive &&
          _index == previous + 1 &&
          previous >= 0 &&
          previous < _tracks.length) {
        final duration = _tracks[previous].durationMs;
        if (duration != null) _sampleJournal(previous, duration, observedAt);
        _resetJournalCapture();
        _sampleJournal(_index, 0, observedAt);
      } else {
        _resetJournalCapture();
      }
    }
    _journalTrackIndex = _index;
    _sampleJournal(_index, _position.inMilliseconds, observedAt);
  }

  _JournalAnchor? _journalAnchor() {
    if (!_journalEnabled ||
        _journalClearing ||
        _currentBookId == null ||
        _index < 0 ||
        _index >= _tracks.length) {
      return null;
    }
    final observedAt = now();
    return _JournalAnchor(
      bookId: _currentBookId!,
      filePath: _tracks[_index].filePath,
      positionMs: _position.inMilliseconds,
      atMs: observedAt.millisecondsSinceEpoch,
      utcOffsetMinutes: observedAt.timeZoneOffset.inMinutes,
      speed: state.speed,
      chapterTitle: _journalChapterTitle(_index, _position.inMilliseconds),
    );
  }

  void _recordJournalEvent(
    String kind, {
    _JournalAnchor? anchor,
    String? targetFilePath,
    int? targetPositionMs,
    String? reason,
  }) {
    if (!_journalEnabled || _journalClearing) return;
    final source = anchor ?? _journalAnchor();
    if (source == null) return;
    _journalEvents.add(
      _JournalEvent(
        id: const Uuid().v4(),
        kind: kind,
        anchor: source,
        targetFilePath: targetFilePath,
        targetPositionMs: targetPositionMs,
        reason: reason ?? (isReturnTrailActive ? 'return_trail' : null),
      ),
    );
  }

  void _recordJournalSeek(_JournalAnchor? from, String reason) {
    if (from == null || _tracks.isEmpty || _index >= _tracks.length) return;
    if (from.filePath == _tracks[_index].filePath &&
        from.positionMs == _position.inMilliseconds) {
      return;
    }
    _recordJournalEvent(
      'seek',
      anchor: from,
      targetFilePath: _tracks[_index].filePath,
      targetPositionMs: _position.inMilliseconds,
      reason: reason,
    );
  }

  Future<void> _flushListeningJournal() async {
    final journal = ListeningJournalService(db);
    for (final passage in _journalPassages.pending) {
      await journal.recordPlayed(
        id: passage.id,
        bookId: passage.bookId,
        filePath: passage.filePath,
        startMs: passage.startMs,
        endMs: passage.endMs,
        startedAtMs: passage.startedAtMs,
        endedAtMs: passage.endedAtMs,
        utcOffsetMinutes: passage.utcOffsetMinutes,
        speed: passage.speed,
        chapterTitle: passage.chapterTitle,
        reason: passage.reason,
      );
      _journalPassages.acknowledge(passage);
    }
    for (final event in List<_JournalEvent>.of(_journalEvents)) {
      final source = event.anchor;
      await journal.recordEvent(
        id: event.id,
        bookId: source.bookId,
        kind: event.kind,
        filePath: source.filePath,
        positionMs: source.positionMs,
        atMs: source.atMs,
        utcOffsetMinutes: source.utcOffsetMinutes,
        speed: source.speed,
        chapterTitle: source.chapterTitle,
        targetFilePath: event.targetFilePath,
        targetPositionMs: event.targetPositionMs,
        reason: event.reason,
      );
      _journalEvents.remove(event);
    }
  }

  Future<void> setListeningJournalEnabled(bool enabled) => _command(() async {
    if (settings == null) throw StateError('Settings are unavailable');
    settings!.listeningJournalEnabled = enabled;
    _syncJournalPreference();
    await _flushListeningJournal();
  });

  Future<void> clearListeningJournal({String? bookId}) => _command(() async {
    _journalClearing = true;
    try {
      _capturePlayedPosition(); // Keep ordinary coverage independent.
      _journalPassages.clear(bookId: bookId);
      _journalEvents.removeWhere(
        (event) => bookId == null || event.anchor.bookId == bookId,
      );
      _resetJournalCapture();
      await ListeningJournalService(db).clear(bookId: bookId);
    } finally {
      _journalClearing = false;
      _resetJournalCapture();
      _captureJournalPosition();
    }
  });

  /// All history stores share this serialized clear boundary. Pausing and
  /// discarding pending captures prevents a later checkpoint recreating rows
  /// that the listener just removed.
  Future<void> clearListeningHistory() => _command(() async {
    _journalClearing = true;
    try {
      // These buffers are part of the requested deletion, even if their last
      // database write failed. Do not require saving them before removing them.
      _playedRanges.clear();
      _journalPassages.clear();
      _journalEvents.clear();
      _resetPlayedCapture();
      if (isReturnTrailActive) await _finishReturnTrail();
      await _pause(reason: 'history_cleared');
      await db.clearAllHistory();
    } finally {
      _journalClearing = false;
      _resetPlayedCapture();
    }
  });

  Future<JournalPage> listeningJournal({
    String? bookId,
    int? fromUtcMs,
    int? beforeUtcMs,
    JournalPassageFilter? passage,
    int limit = 50,
    String? cursor,
  }) async {
    late JournalPage page;
    await _command(() async {
      _captureJournalPosition();
      await _flushListeningJournal();
      page = await ListeningJournalService(db).page(
        bookId: bookId,
        fromUtcMs: fromUtcMs,
        beforeUtcMs: beforeUtcMs,
        passage: passage,
        limit: limit,
        cursor: cursor,
      );
    });
    return page;
  }

  /// Capture pending playback evidence and read a complete filtered snapshot in
  /// the same command. Export formatting and file I/O happen after this returns.
  Future<List<ListeningJournalEntry>> listeningJournalSnapshot({
    String? bookId,
    int? fromUtcMs,
    int? beforeUtcMs,
    JournalPassageFilter? passage,
  }) async {
    late List<ListeningJournalEntry> snapshot;
    await _command(() async {
      _captureJournalPosition();
      await _flushListeningJournal();
      snapshot = await ListeningJournalService(db).snapshot(
        bookId: bookId,
        fromUtcMs: fromUtcMs,
        beforeUtcMs: beforeUtcMs,
        passage: passage,
      );
    });
    return snapshot;
  }

  /// Open historical evidence paused, with a durable bookmark for the previous
  /// place. Validate stale/missing destinations before changing active audio.
  Future<String?> resumeJournalPosition({
    required String bookId,
    required String filePath,
    required int positionMs,
  }) async {
    String? savedBookmark;
    await _command(() async {
      final book = await db.getBook(bookId);
      if (book == null) throw StateError('This journal book is unavailable.');
      final tracks = await db.tracksFor(bookId);
      final targetIndex = tracks.indexWhere(
        (track) => track.filePath == filePath,
      );
      if (targetIndex < 0) {
        throw StateError('This journal track is unavailable.');
      }
      final duration = tracks[targetIndex].durationMs;
      if (positionMs < 0 || (duration != null && positionMs > duration)) {
        throw RangeError.range(positionMs, 0, duration, 'positionMs');
      }
      if (duration == null && positionMs > 0) {
        final evidence =
            await (db.select(db.listeningJournal)
                  ..where(
                    (entry) =>
                        entry.bookId.equals(bookId) &
                        ((entry.filePath.equals(filePath) &
                                entry.endMs.isBiggerOrEqualValue(positionMs)) |
                            (entry.targetFilePath.equals(filePath) &
                                entry.targetPositionMs.isBiggerOrEqualValue(
                                  positionMs,
                                ))),
                  )
                  ..limit(1))
                .getSingleOrNull();
        if (evidence == null) {
          throw StateError(
            'No journal position exists at this unknown track offset.',
          );
        }
      }
      _wasPlayingBeforeInterruption = false;
      _trailResumeRequested = false;
      _returnTrailTimer?.cancel();
      if (isReturnTrailActive) await _finishReturnTrail();
      if (_currentBookId != null &&
          _tracks.isNotEmpty &&
          (_currentBookId != bookId ||
              _tracks[_index].filePath != filePath ||
              _position.inMilliseconds != positionMs)) {
        savedBookmark = await bookmarks.addManual(
          bookId: _currentBookId!,
          filePath: _tracks[_index].filePath,
          position: _position,
          bookPosition: bookPosition,
          title: 'Before journal jump',
          note: 'Saved before opening a position from the listening journal.',
        );
      }
      await _pause(reason: 'journal_resume');
      if (_currentBookId != bookId) await _loadBook(bookId);
      final index = _tracks.indexWhere((track) => track.filePath == filePath);
      if (index < 0) throw StateError('This journal track is unavailable.');
      await _seekTrack(
        index,
        Duration(milliseconds: positionMs),
        journalReason: 'journal_resume',
      );
      _pausedAt = null;
    });
    return savedBookmark;
  }

  void _resetPlayedCapture({bool journal = true}) {
    _playedRanges.reset();
    _capturedTrackIndex = null;
    if (journal) _resetJournalCapture();
  }

  void _capturePlayedPosition({bool completed = false}) {
    _captureJournalPosition(completed: completed);
    if (_loading ||
        _seeking ||
        isReturnTrailActive ||
        !_backendReady ||
        (_backend?.playing != true && !(completed && state.isPlaying)) ||
        _currentBookId == null ||
        _index < 0 ||
        _index >= _tracks.length) {
      return;
    }
    // Some native backends publish the new position before the index stream.
    _captureNaturalTrackEnd(_index);
    _capturedTrackIndex = _index;
    _playedRanges.sample(
      bookId: _currentBookId!,
      filePath: _tracks[_index].filePath,
      positionMs: _position.inMilliseconds,
      observedAtMs: now().millisecondsSinceEpoch,
      speed: state.speed,
    );
  }

  void _captureNaturalTrackEnd(int nextIndex) {
    final previous = _capturedTrackIndex;
    if (_loading ||
        _seeking ||
        isReturnTrailActive ||
        !_backendReady ||
        _backend?.playing != true ||
        _currentBookId == null ||
        previous == null ||
        previous < 0 ||
        previous >= _tracks.length ||
        nextIndex != previous + 1) {
      return;
    }
    final endMs = _tracks[previous].durationMs;
    if (endMs != null) {
      // An adjacent native source transition confirms a file boundary. The
      // recorder still rejects a tail too long for elapsed playback time.
      _playedRanges.sample(
        bookId: _currentBookId!,
        filePath: _tracks[previous].filePath,
        positionMs: endMs,
        observedAtMs: now().millisecondsSinceEpoch,
        speed: state.speed,
      );
    }
    _resetPlayedCapture(journal: false);
    _capturedTrackIndex = nextIndex;
    _playedRanges.sample(
      bookId: _currentBookId!,
      filePath: _tracks[nextIndex].filePath,
      positionMs: 0,
      observedAtMs: now().millisecondsSinceEpoch,
      speed: state.speed,
    );
  }

  Future<void> _flushPlayedRanges() async {
    final store = ReturnTrailService(db);
    for (final range in _playedRanges.pending) {
      await store.record(
        bookId: range.bookId,
        filePath: range.filePath,
        startMs: range.startMs,
        endMs: range.endMs,
        heardAtMs: range.heardAtMs,
      );
      _playedRanges.acknowledge(range);
    }
    await _flushListeningJournal();
  }

  /// Return unique recorded coverage, including the latest pending samples.
  /// This is separate from the current playhead and the recent replay buffer.
  Future<BookListeningCoverage> listeningCoverage({String? bookId}) async {
    late BookListeningCoverage coverage;
    await _command(() async {
      final id = bookId ?? _currentBookId;
      if (id == null || await db.getBook(id) == null) {
        throw StateError('Choose an available book to view its listening map.');
      }
      _capturePlayedPosition();
      await _flushPlayedRanges();
      coverage = await ListeningCoverageService(db).forBook(id);
    });
    return coverage;
  }

  /// An explicit map jump selects a physical position paused. Validation runs
  /// before ending a trail, so a stale sheet cannot disturb another book.
  Future<void> seekCoverage({
    required String bookId,
    required String filePath,
    required int positionMs,
  }) => _command(() async {
    if (bookId != _currentBookId || _tracks.isEmpty) {
      throw StateError('The selected book is no longer open.');
    }
    final index = _tracks.indexWhere((track) => track.filePath == filePath);
    if (index < 0) throw StateError('This track is no longer in the book.');
    if (positionMs < 0) {
      throw RangeError.range(positionMs, 0, null, 'positionMs');
    }
    var extent = _tracks[index].durationMs;
    if (extent == null) {
      _capturePlayedPosition();
      await _flushPlayedRanges();
      final coverage = await ListeningCoverageService(db).forBook(bookId);
      extent = coverage.tracks
          .firstWhere((track) => track.filePath == filePath)
          .timelineExtentMs;
    }
    if (positionMs > extent) {
      throw RangeError.range(positionMs, 0, extent, 'positionMs');
    }
    _wasPlayingBeforeInterruption = false;
    _trailResumeRequested = false;
    _returnTrailTimer?.cancel();
    if (isReturnTrailActive) await _finishReturnTrail();
    await _pause();
    await _seekTrack(
      index,
      Duration(milliseconds: positionMs),
      journalReason: 'coverage_jump',
    );
    _pausedAt = null; // Explicit map jumps should not smart-rewind on Play.
  });

  TrailAnchor _trailAnchor(String? expectedBookId) {
    if (_currentBookId == null ||
        _tracks.isEmpty ||
        (expectedBookId != null && expectedBookId != _currentBookId)) {
      throw StateError('The selected book is no longer open.');
    }
    return TrailAnchor(
      bookId: _currentBookId!,
      filePath: _tracks[_index].filePath,
      positionMs: _position.inMilliseconds,
    );
  }

  Future<ReturnTrailPlan> previewReturnTrail({
    Duration budget = const Duration(seconds: 60),
    String? expectedBookId,
  }) async {
    late ReturnTrailPlan plan;
    await _command(() async {
      final anchor = _trailAnchor(expectedBookId);
      if (isReturnTrailActive) {
        plan = _returnTrailPlan!;
        return;
      }
      _capturePlayedPosition();
      await _flushPlayedRanges();
      plan = await ReturnTrailService(
        db,
      ).plan(anchor: anchor, budget: budget, speed: state.speed);
    });
    return plan;
  }

  Future<void> startReturnTrail({
    Duration budget = const Duration(seconds: 60),
    String? expectedBookId,
  }) => _command(() async {
    _trailAnchor(expectedBookId);
    if (isReturnTrailActive) return;
    // Validate the budget before changing playback or creating a bookmark.
    if (budget < const Duration(seconds: 15) ||
        budget > const Duration(minutes: 5)) {
      throw ArgumentError('Choose 15 to 300 seconds of listening time.');
    }
    final wasPlaying = _backend!.playing;
    _capturePlayedPosition();
    await _backend!.pause();
    _resetPlayedCapture();
    await _persistProgress();
    await _endSession();
    final anchor = _trailAnchor(expectedBookId);
    final plan = await ReturnTrailService(
      db,
    ).plan(anchor: anchor, budget: budget, speed: state.speed);
    if (plan.clips.isEmpty) {
      if (wasPlaying) await _play();
      throw StateError('Listen to this book first to build a Return Trail.');
    }
    // The normal database resume point is already saved. This extra bookmark
    // remains useful even if a decoder fails or the application is terminated.
    await db.transaction(() async {
      await db.insertBookmark(
        BookmarksCompanion.insert(
          id: const Uuid().v4(),
          bookId: anchor.bookId,
          title: 'Return Trail · saved place',
          note: const Value(
            'Your place before revisiting previously played audio.',
          ),
          kind: const Value('return-trail'),
          filePath: anchor.filePath,
          positionMs: anchor.positionMs,
          bookPositionMs: bookPosition.inMilliseconds,
          createdAtMs: now().millisecondsSinceEpoch,
        ),
      );
      final saved = (await db.bookmarksFor(
        anchor.bookId,
      )).where((b) => b.kind == 'return-trail').toList();
      for (final old in saved.skip(5)) {
        await db.deleteBookmark(old.id);
      }
    });
    _returnTrailPlan = plan;
    _returnTrailClipIndex = 0;
    _trailGeneration++;
    _trailAdvancePending = false;
    _trailResumeRequested = true;
    _pausedAt = null;
    _resetPlayedCapture();
    _emit(state);
    try {
      await _seekReturnTrailClip(0, play: true);
    } catch (_) {
      _trailResumeRequested = false;
      _returnTrailTimer?.cancel();
      await _backend!.pause();
      // Leave the protected plan available for an explicit retry/return.
      rethrow;
    }
  });

  Future<void> nextReturnTrailClip() => _command(_advanceReturnTrail);

  Future<void> _advanceReturnTrail() async {
    final plan = _returnTrailPlan;
    if (plan == null || _trailTransitioning) return;
    final next = _returnTrailClipIndex + 1;
    if (next >= plan.clips.length) {
      await _finishReturnTrail();
    } else {
      await _seekReturnTrailClip(
        next,
        play: _trailResumeRequested && _backend!.playing,
      );
    }
  }

  Future<void> _seekReturnTrailClip(
    int index, {
    Duration? position,
    required bool play,
  }) async {
    final plan = _returnTrailPlan;
    if (plan == null) return;
    final clip = plan.clips[index];
    _captureJournalPosition();
    final from = _journalAnchor();
    _resetJournalCapture();
    _returnTrailTimer?.cancel();
    _trailGeneration++;
    _trailAdvancePending = false;
    _trailTransitioning = true;
    try {
      await _backend!.pause();
      _returnTrailClipIndex = index;
      await _backend!.seek(
        Duration(
          milliseconds: (position?.inMilliseconds ?? clip.startMs).clamp(
            clip.startMs,
            clip.endMs,
          ),
        ),
        index: clip.trackIndex,
      );
      _recordJournalSeek(from, 'return_trail');
    } finally {
      _trailTransitioning = false;
      _publishPosition();
    }
    if (play && _trailResumeRequested) {
      await _playReturnTrailAudio();
    } else {
      _emit(state.copyWith(status: m.PlaybackStatus.paused));
    }
  }

  Future<void> _playReturnTrailAudio() async {
    if (!isReturnTrailActive || !_trailResumeRequested) return;
    final clip = _returnTrailPlan!.clips[_returnTrailClipIndex];
    if (_index != clip.trackIndex ||
        _position.inMilliseconds < clip.startMs ||
        _position.inMilliseconds >= clip.endMs) {
      // A failed seek may leave the decoder at the original anchor. Retrying
      // Play must re-establish the selected excerpt before it can emit audio.
      await _seekReturnTrailClip(_returnTrailClipIndex, play: false);
    }
    if (_audioSession != null && !await _audioSession!.setActive(true)) {
      throw StateError('Audio session unavailable');
    }
    // A pause, interruption or sleep expiry may arrive during activation.
    if (!_trailResumeRequested || !isReturnTrailActive) return;
    _background(
      _backend!.play().catchError((Object error) async {
        _trailResumeRequested = false;
        _returnTrailTimer?.cancel();
        _emit(
          state.copyWith(
            status: m.PlaybackStatus.error,
            error: error.toString(),
          ),
        );
      }),
    );
    _scheduleReturnTrailEnd();
  }

  void _scheduleReturnTrailEnd() {
    _returnTrailTimer?.cancel();
    if (!isReturnTrailActive ||
        _trailTransitioning ||
        !_trailResumeRequested ||
        _backend?.playing != true ||
        !_backendReady) {
      return;
    }
    final clip = _returnTrailPlan!.clips[_returnTrailClipIndex];
    final remaining = clip.endMs - _position.inMilliseconds;
    final generation = _trailGeneration;
    _returnTrailTimer = Timer(
      Duration(
        milliseconds: (remaining / state.speed).ceil().clamp(0, 3600000),
      ),
      () {
        if (generation != _trailGeneration) return;
        _checkReturnTrailEnd();
        if (!_trailAdvancePending && isReturnTrailActive) {
          _scheduleReturnTrailEnd();
        }
      },
    );
  }

  void _checkReturnTrailEnd() {
    if (!isReturnTrailActive ||
        _trailTransitioning ||
        _backend?.playing != true ||
        !_trailResumeRequested) {
      return;
    }
    final clip = _returnTrailPlan!.clips[_returnTrailClipIndex];
    if (_index != clip.trackIndex || _position.inMilliseconds >= clip.endMs) {
      _queueReturnTrailAdvance(_trailGeneration);
    }
  }

  void _queueReturnTrailAdvance(int generation) {
    if (!isReturnTrailActive ||
        generation != _trailGeneration ||
        _trailAdvancePending ||
        !_trailResumeRequested) {
      return;
    }
    _trailAdvancePending = true;
    _returnTrailTimer?.cancel();
    _background(
      _command(() async {
        try {
          if (generation != _trailGeneration ||
              !isReturnTrailActive ||
              !_trailResumeRequested ||
              _backend?.playing != true) {
            return;
          }
          await _advanceReturnTrail();
        } finally {
          if (generation == _trailGeneration) _trailAdvancePending = false;
        }
      }),
    );
  }

  Future<void> finishReturnTrail({bool continueHere = false}) {
    // Invalidate automatic transitions immediately, before entering the queue.
    _trailResumeRequested = false;
    _returnTrailTimer?.cancel();
    return _command(() => _finishReturnTrail(continueHere: continueHere));
  }

  Future<void> _finishReturnTrail({bool continueHere = false}) async {
    final plan = _returnTrailPlan;
    if (plan == null) return;
    _captureJournalPosition();
    final from = _journalAnchor();
    if (_backend!.playing) {
      _recordJournalEvent('pause', reason: 'return_trail_ended');
    }
    _resetJournalCapture();
    _trailGeneration++;
    _trailResumeRequested = false;
    _trailAdvancePending = false;
    _returnTrailTimer?.cancel();
    await _backend!.pause();
    if (!continueHere) {
      final index = _tracks.indexWhere(
        (t) => t.filePath == plan.anchor.filePath,
      );
      if (index < 0) throw StateError('The saved return file is unavailable.');
      await _backend!.seek(
        Duration(milliseconds: plan.anchor.positionMs),
        index: index,
      );
    } else {
      final clip = plan.clips[_returnTrailClipIndex];
      // A delayed native callback can have crossed a file boundary. Explicit
      // adoption still stays within the passage the listener was reviewing.
      await _backend!.seek(
        Duration(
          milliseconds: _index == clip.trackIndex
              ? _position.inMilliseconds.clamp(clip.startMs, clip.endMs)
              : clip.endMs,
        ),
        index: clip.trackIndex,
      );
    }
    _recordJournalSeek(
      from,
      continueHere ? 'return_trail_continue' : 'return_trail_return',
    );
    _returnTrailPlan = null;
    _returnTrailClipIndex = 0;
    _pausedAt = null;
    _resetPlayedCapture();
    _publishPosition();
    await _persistProgress();
    _emit(state.copyWith(status: m.PlaybackStatus.paused));
    if (continueHere) await _play();
  }

  void _publishPosition() {
    if (_loading || _tracks.isEmpty || _index >= _tracks.length) return;
    _emit(
      state.copyWith(
        position: _position,
        duration:
            _backend?.duration ??
            Duration(milliseconds: _tracks[_index].durationMs ?? 0),
        currentIndex: _index,
        currentFile: _tracks[_index].filePath,
      ),
    );
  }

  void _emit(m.PlaybackState next) {
    _state = next;
    if (!_stateCtrl.isClosed) _stateCtrl.add(next);
  }

  Future<void> _persistProgress() async {
    _capturePlayedPosition();
    await _flushPlayedRanges();
    if (isReturnTrailActive) return;
    if (_currentBookId == null || _tracks.isEmpty || _index >= _tracks.length) {
      return;
    }
    await library.updateProgress(
      _currentBookId!,
      _tracks[_index].filePath,
      _position,
      bookPosition,
      bookDuration ?? Duration.zero,
      isPlaying: _backend?.playing == true,
    );
    if (_activeSessionId != null) {
      await history.endSession(
        _activeSessionId!,
        bookPosition,
        _sessionClock!.elapsed,
        close: false,
      );
    }
  }

  void _startAutoBookmark() {
    _autoBookmarkTimer?.cancel();
    if (_currentBookId == null || settings?.autoBookmarkEnabled == false) {
      return;
    }
    _autoBookmarkTimer = Timer.periodic(
      settings?.autoBookmarkInterval ?? const Duration(minutes: 5),
      (_) {
        if (_backend?.playing == true) {
          _background(_command(_maybeAutoBookmark));
        }
      },
    );
  }

  Future<void> _maybeAutoBookmark() async {
    if (isReturnTrailActive ||
        settings?.autoBookmarkEnabled == false ||
        _currentBookId == null ||
        _tracks.isEmpty ||
        _position == Duration.zero) {
      return;
    }
    await bookmarks.addAuto(
      bookId: _currentBookId!,
      filePath: _tracks[_index].filePath,
      position: _position,
      bookPosition: bookPosition,
    );
    await bookmarks.pruneAuto(_currentBookId!);
  }

  Future<void> _startSession() async {
    if (isReturnTrailActive ||
        _activeSessionId != null ||
        _currentBookId == null) {
      return;
    }
    _sessionClock = Stopwatch()..start();
    _activeSessionId = await history.startSession(
      bookId: _currentBookId!,
      startPos: bookPosition,
      speed: state.speed,
    );
  }

  Future<void> _endSession() async {
    await _flushPlayedRanges();
    if (_activeSessionId == null) return;
    final id = _activeSessionId!;
    final elapsed = _sessionClock!.elapsed;
    _sessionClock!.stop();
    _activeSessionId = null;
    _sessionClock = null;
    await history.endSession(id, bookPosition, elapsed);
  }

  Duration get rewindAmount => Duration(
    seconds:
        _bookPreferences['smartRewindSeconds'] as int? ??
        settings?.smartRewindSeconds ??
        5,
  );
  Duration get rewindThreshold => Duration(
    seconds:
        _bookPreferences['smartRewindAfterSeconds'] as int? ??
        settings?.smartRewindAfterSeconds ??
        60,
  );
  bool shouldSmartRewind(DateTime pausedAt, {DateTime? now}) =>
      rewindAmount > Duration.zero &&
      (now ?? this.now()).difference(pausedAt) > rewindThreshold;
  Duration applySmartRewind(Duration pos) =>
      pos < rewindAmount ? Duration.zero : pos - rewindAmount;

  /// Flush position on backgrounding; the listening session continues with audio.
  Future<void> handleAppPaused() => _command(_persistProgress);
  Future<void> handleAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) _tickSleep();
    if (state == AppLifecycleState.paused) await handleAppPaused();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _background(handleAppLifecycleState(state));
  }

  Future<void> dispose() async {
    if (_disposed) return;
    settings?.removeListener(_settingsChanged);
    library.beforeDelete = null;
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    _progressTimer?.cancel();
    _autoBookmarkTimer?.cancel();
    _sleepTimer?.cancel();
    _returnTrailTimer?.cancel();
    _trailResumeRequested = false;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _commands;
    // A settings command already in flight can restart this timer while the
    // command queue drains, after the initial cancellation above.
    _autoBookmarkTimer?.cancel();
    _returnTrailTimer?.cancel();
    if (_currentBookId != null) {
      _capturePlayedPosition();
      _recordJournalEvent('close', reason: 'app_closed');
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

class _JournalAnchor {
  final String bookId;
  final String filePath;
  final int positionMs;
  final int atMs;
  final int utcOffsetMinutes;
  final double speed;
  final String? chapterTitle;

  const _JournalAnchor({
    required this.bookId,
    required this.filePath,
    required this.positionMs,
    required this.atMs,
    required this.utcOffsetMinutes,
    required this.speed,
    this.chapterTitle,
  });
}

class _JournalEvent {
  final String id;
  final String kind;
  final _JournalAnchor anchor;
  final String? targetFilePath;
  final int? targetPositionMs;
  final String? reason;

  const _JournalEvent({
    required this.id,
    required this.kind,
    required this.anchor,
    this.targetFilePath,
    this.targetPositionMs,
    this.reason,
  });
}
