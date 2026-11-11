import 'dart:io';

import 'package:crisper_audio/crisper_audio.dart';
import 'package:crisperplayer/services/audio/native_audio_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState, PlayerState;

import 'support/audio_fixture.dart';

void main() {
  final library = Platform.environment['CRISPER_AUDIO_LIBRARY_PATH'];
  if (Platform.environment['CRISPER_REQUIRE_NATIVE_AUDIO'] == '1' &&
      library == null) {
    throw StateError('Native CI requires CRISPER_AUDIO_LIBRARY_PATH');
  }
  final skip = library == null
      ? 'Requires the controlled native audio library'
      : false;
  late Directory directory;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('crisper-backend-test-');
  });
  tearDown(() => directory.deleteSync(recursive: true));

  test(
    'real native source events are ordered and completion retains play intent',
    () async {
      final first = await writeTestWav(
        File('${directory.path}/first.wav'),
        seconds: 1,
      );
      final second = await writeTestWav(
        File('${directory.path}/second.wav'),
        seconds: 2,
      );
      final player = NativeAudioPlayer(
        libraryPath: library,
        testOutput: true,
        bufferFrames: 1024,
      );
      final backend = NativeAudioBackend(player: player);
      addTearDown(backend.dispose);
      final events = <String>[];
      final errors = <Object>[];
      final states = <PlayerState>[];
      var ready = false;
      var newSourceObservedWhileReady = false;
      final subscriptions = [
        backend.states.listen((state) {
          states.add(state);
          ready = state.processingState == ProcessingState.ready;
          events.add(
            'state:${state.processingState.name}:${backend.currentIndex}',
          );
        }, onError: errors.add),
        backend.indices.listen((index) => events.add('index:$index')),
        backend.durations.listen(
          (duration) => events.add('duration:${duration!.inMicroseconds}'),
        ),
        backend.positions.listen((position) {
          events.add(
            'position:${backend.currentIndex}:${position.inMicroseconds}',
          );
          if (backend.currentIndex == 1 && position == Duration.zero) {
            newSourceObservedWhileReady |= ready;
          }
        }),
      ];
      addTearDown(() async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      });
      await backend.load(
        [first.path, second.path],
        index: 0,
        position: Duration.zero,
      );
      await backend.play();
      var presented = 0;
      for (
        var i = 0;
        i < 200 && player.state != NativeAudioState.completed;
        i++
      ) {
        presented += await player.pump(511);
      }
      expect(presented, 16000 + 32000);
      expect(backend.currentIndex, 1);
      expect(backend.duration, const Duration(seconds: 2));
      expect(backend.position, const Duration(seconds: 2));
      expect(states.last.processingState, ProcessingState.completed);
      expect(states.last.playing, isTrue);
      expect(backend.playing, isTrue);
      expect(
        newSourceObservedWhileReady,
        isFalse,
        reason:
            'The coordinator must leave ready before seeing a new source position',
      );
      final previousEnd = events.indexOf('position:0:1000000');
      final loading = events.indexOf('state:loading:0', previousEnd);
      final nextIndex = events.indexOf('index:1');
      final nextDuration = events.indexOf('duration:2000000');
      final nextPosition = events.indexOf('position:1:0');
      final nextReady = events.indexOf('state:ready:1');
      expect(previousEnd, greaterThanOrEqualTo(0));
      expect(loading, greaterThan(previousEnd));
      expect(nextIndex, greaterThan(loading));
      expect(nextDuration, greaterThan(nextIndex));
      expect(nextPosition, greaterThan(nextDuration));
      expect(nextReady, greaterThan(nextPosition));
      expect(errors, isEmpty);
      await backend.pause();
      expect(states.last.playing, isFalse);
    },
    skip: skip,
  );

  test(
    'adapter suppresses superseded transport, preserving real failures',
    () async {
      final file = await writeTestWav(
        File('${directory.path}/source.wav'),
        seconds: 1,
      );
      final player = NativeAudioPlayer(libraryPath: library, testOutput: true);
      final backend = NativeAudioBackend(player: player);
      addTearDown(backend.dispose);
      final errors = <Object>[];
      final subscription = backend.states.listen((_) {}, onError: errors.add);
      addTearDown(subscription.cancel);
      final obsolete = backend.load(
        [file.path],
        index: 0,
        position: Duration.zero,
      );
      final current = backend.load(
        [file.path],
        index: 0,
        position: const Duration(milliseconds: 250),
      );
      await Future.wait([obsolete, current]);
      expect(backend.position, const Duration(milliseconds: 250));
      expect(errors, isEmpty);
      await expectLater(
        backend.load(
          ['${directory.path}/missing.wav'],
          index: 0,
          position: Duration.zero,
        ),
        throwsA(isA<NativeAudioError>()),
      );
      expect(errors, hasLength(1));
      expect(backend.playing, isFalse);
      await expectLater(backend.play(), throwsA(isA<NativeAudioError>()));
      expect(errors, hasLength(1));
    },
    skip: skip,
  );

  test(
    'initialization failure is replayed to a later coordinator subscriber',
    () async {
      final player = NativeAudioPlayer(
        libraryPath: '${directory.path}/missing-native-library',
      );
      // Library open can fail inside the player constructor, before the adapter
      // and PlaybackService have had a chance to attach stream listeners.
      final backend = NativeAudioBackend(player: player);
      addTearDown(backend.dispose);
      final errors = <Object>[];
      final states = <PlayerState>[];
      final subscription = backend.states.listen(
        states.add,
        onError: errors.add,
      );
      addTearDown(subscription.cancel);
      await Future<void>.delayed(Duration.zero);
      expect(states.last.processingState, ProcessingState.idle);
      expect(states.last.playing, isFalse);
      expect(errors, hasLength(1));
      expect(errors.single, isA<NativeAudioError>());
      await expectLater(backend.play(), throwsA(isA<NativeAudioError>()));
      expect(errors, hasLength(1));
    },
  );
}
