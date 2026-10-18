import 'dart:async';
import 'dart:io';
import 'package:crisperplayer/services/audio/audio_backend.dart';
import 'package:crisperplayer/services/audio/android_audio_effects.dart';
import 'package:crisperplayer/services/audio/playback_service.dart';
import 'package:crisperplayer/services/bookmark_service.dart';
import 'package:crisperplayer/services/db/app_database.dart';
import 'package:crisperplayer/services/history_service.dart';
import 'package:crisperplayer/services/library_service.dart';
import 'package:crisperplayer/services/settings_service.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Implements the native player's completion semantics: play stays pending until
/// paused or stopped. Tests exercise the real coordinator and database above it.
class FakeAudioBackend implements AudioBackend, AudioEffectsBackend {
  @override
  bool get supportsAudioEffects => true;
  @override
  String? get audioEffectsError => null;
  double boostDb = 0;
  String equalizer = 'off';
  @override
  Future<void> setAudioEffects({required double boostDb, required String equalizer}) async {
    this.boostDb = boostDb; this.equalizer = equalizer;
  }
  @override
  bool get supportsSkipSilence => true;
  final _positions = StreamController<Duration>.broadcast(sync: true);
  final _states = StreamController<PlayerState>.broadcast(sync: true);
  final _durations = StreamController<Duration?>.broadcast(sync: true);
  final _indices = StreamController<int?>.broadcast(sync: true);
  @override
  Duration position = Duration.zero;
  @override
  Duration? duration;
  @override
  int currentIndex = 0;
  @override
  bool playing = false;
  double speed = 1;
  double volume = 1;
  bool skipSilence = false;
  bool failLoad = false;
  bool disposed = false;
  Completer<void>? _playback;
  List<String> paths = [];
  @override
  Stream<Duration> get positions => _positions.stream;
  @override
  Stream<PlayerState> get states => _states.stream;
  @override
  Stream<Duration?> get durations => _durations.stream;
  @override
  Stream<int?> get indices => _indices.stream;
  void move(Duration position, {int? index}) {
    if (index != null) {
      currentIndex = index;
      _indices.add(index);
    }
    this.position = position;
    _positions.add(position);
  }

  void complete() {
    _states.add(PlayerState(playing, ProcessingState.completed));
  }

  void buffer() {
    _states.add(PlayerState(playing, ProcessingState.buffering));
  }

  void ready() {
    _states.add(PlayerState(playing, ProcessingState.ready));
  }

  @override
  Future<void> load(List<String> paths,
      {required int index, required Duration position}) async {
    if (failLoad) throw StateError('Decoder failed');
    this.paths = paths;
    currentIndex = index;
    this.position = position;
    playing = false;
    _indices.add(index);
    _positions.add(position);
    _states.add(PlayerState(false, ProcessingState.ready));
  }

  @override
  Future<void> play() {
    if (playing) return Future.value();
    playing = true;
    _playback = Completer<void>();
    ready();
    return _playback!.future;
  }

  @override
  Future<void> pause() async {
    playing = false;
    _playback?.complete();
    _playback = null;
    _states.add(PlayerState(false, ProcessingState.ready));
  }

  @override
  Future<void> stop() async {
    await pause();
  }

  @override
  Future<void> seek(Duration position, {int? index}) async {
    move(position, index: index);
  }

  @override
  Future<void> setSpeed(double speed) async {
    this.speed = speed;
  }

  @override
  Future<void> setVolume(double volume) async {
    this.volume = volume;
  }

  @override
  Future<void> setSkipSilence(bool enabled) async {
    skipSilence = enabled;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    _playback?.complete();
    _playback = null;
    await _positions.close();
    await _states.close();
    await _durations.close();
    await _indices.close();
  }
}

class PlaybackHarness {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final backend = FakeAudioBackend();
  final Directory root = Directory.systemTemp.createTempSync('crisper_test_');
  late final SettingsService settings;
  late final LibraryService library;
  late final PlaybackService playback;
  DateTime clock = DateTime(2026);
  Future<void> init({Map<String, Object> preferences = const {}}) async {
    SharedPreferences.setMockInitialValues(preferences);
    settings = SettingsService(await SharedPreferences.getInstance());
    library = LibraryService(db,
        storageDirectory: () async => root, probeDuration: (_) async => null);
    playback = PlaybackService(
        db: db,
        library: library,
        bookmarks: BookmarkService(db),
        history: HistoryService(db),
        backend: backend,
        settings: settings,
        now: () => clock);
    await playback.init();
  }

  Future<void> book(String id, List<int> durationSeconds) async {
    final paths = List.generate(durationSeconds.length, (i) => '/$id/$i.mp3');
    await db.upsertBook(BooksCompanion.insert(
        id: id,
        title: id,
        filePathsJson: AppDatabase.encodePaths(paths),
        addedAtMs: 0,
        totalDurationMs:
            Value(durationSeconds.fold(0, (a, b) => a + b) * 1000)));
    await db.replaceTracks(id, [
      for (var i = 0; i < paths.length; i++)
        BookTracksCompanion.insert(
            bookId: id,
            trackIndex: i,
            filePath: paths[i],
            durationMs: Value(durationSeconds[i] * 1000))
    ]);
    var start = 0;
    await db.replaceChapters(id, [
      for (var i = 0; i < paths.length; i++)
        ChaptersCompanion.insert(
            id: '$id-$i',
            bookId: id,
            title: 'Chapter $i',
            startMs: start,
            endMs: start += durationSeconds[i] * 1000,
            filePath: Value(paths[i]),
            trackIndex: Value(i))
    ]);
  }

  /// Lifecycle flush is a public command and waits behind pending player events.
  Future<void> flush() => playback.handleAppPaused();
  Future<void> dispose() async {
    await playback.dispose();
    await db.close();
    settings.dispose();
    await root.delete(recursive: true);
  }
}
