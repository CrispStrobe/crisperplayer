import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:just_audio_media_kit/mediakit_player.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:media_kit/media_kit.dart';

class _NativeEvents extends PlatformPlayer {
  _NativeEvents() : super(configuration: const PlayerConfiguration());

  Completer<void>? opening;
  int pauses = 0;
  int stops = 0;
  int plays = 0;
  int disposals = 0;
  bool failPauseAndStop = false;

  void log(String prefix, String level, String text) {
    logController.add(PlayerLog(prefix: prefix, level: level, text: text));
  }

  void lateOrdinaryEvents() {
    bufferingController.add(false);
    bufferController.add(const Duration(seconds: 20));
    positionController.add(const Duration(seconds: 15));
    durationController.add(const Duration(seconds: 60));
    completedController.add(true);
    errorController.add('A later unrelated native error');
  }

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    final playlist =
        playable is Playlist ? playable : Playlist([playable as Media]);
    state = state.copyWith(playlist: playlist, playing: play);
    if (opening != null) await opening!.future;
  }

  @override
  Future<void> play() async {
    ++plays;
    state = state.copyWith(playing: true);
  }

  @override
  Future<void> pause() async {
    ++pauses;
    if (failPauseAndStop) throw StateError('pause failed');
    state = state.copyWith(playing: false);
  }

  @override
  Future<void> stop() async {
    ++stops;
    if (failPauseAndStop) throw StateError('stop failed');
    state = state.copyWith(playing: false);
    lateOrdinaryEvents();
  }

  @override
  Future<void> dispose() async {
    ++disposals;
    await super.dispose();
  }
}

LoadRequest _load() => LoadRequest(
      audioSourceMessage: ProgressiveAudioSourceMessage(
        id: 'fixture',
        uri: 'file:///fixture.wav',
      ),
    );

Future<void> _deliverEvents() => Future<void>.delayed(Duration.zero);

void main() {
  test('processor failure during open stops playback and remains an error',
      () async {
    final native = _NativeEvents()..opening = Completer<void>();
    final adapter = MediaKitPlayer.withPlayer(
      'failure',
      Player(platformPlayer: native),
      MediaKitSpeedProcessor.sonic,
    );
    final events = <PlaybackEventMessage>[];
    final data = <PlayerDataMessage>[];
    final eventSubscription =
        adapter.playbackEventMessageStream.listen(events.add);
    final dataSubscription = adapter.playerDataMessageStream.listen(data.add);
    await adapter.play(PlayRequest());
    final loading = adapter.load(_load());
    final rejectedLoad =
        expectLater(loading, throwsA(isA<PlatformException>()));

    native.log('af/crisperdsp', 'error',
        'crisperdsp: Only mono and stereo PCM are supported');
    await _deliverEvents();
    expect(native.pauses, 1);
    expect(native.stops, 1);
    expect(native.state.playing, isFalse);
    expect(data.last.playing, isFalse);
    await rejectedLoad.timeout(const Duration(seconds: 5));
    // Loading has already failed while the native open future remains pending.
    expect(native.opening!.isCompleted, isFalse);
    native.opening!.complete();

    native.lateOrdinaryEvents();
    await _deliverEvents();
    expect(events.last.processingState, ProcessingStateMessage.idle);
    expect(events.last.errorCode, MediaKitPlayer.kErrorCode);
    expect(events.last.errorMessage, contains('Only mono and stereo PCM'));
    expect(events.last.updatePosition, Duration.zero);
    await expectLater(
        adapter.play(PlayRequest()), throwsA(isA<PlatformException>()));
    await expectLater(adapter.load(_load()), throwsA(isA<PlatformException>()));
    await expectLater(
        adapter.seek(SeekRequest(position: const Duration(seconds: 3))),
        throwsA(isA<PlatformException>()));
    expect(() => adapter.setSpeed(SetSpeedRequest(speed: 2)),
        throwsA(isA<PlatformException>()));
    expect(native.plays, 0);

    await eventSubscription.cancel();
    await dataSubscription.cancel();
    await adapter.release();
    expect(native.disposals, 1);
  });

  test('mpv disabling the selected label is fatal for every optional engine',
      () async {
    for (final engine in MediaKitSpeedProcessor.values
        .where((engine) => engine.audioFilter != null)) {
      final native = _NativeEvents();
      final adapter = MediaKitPlayer.withPlayer(
          'label-${engine.name}', Player(platformPlayer: native), engine);
      final events = <PlaybackEventMessage>[];
      final subscription =
          adapter.playbackEventMessageStream.listen(events.add);
      native.log('af', 'error',
          'Disabling filter crisper_speed because it has failed.');
      await _deliverEvents();
      expect(native.stops, 1, reason: engine.name);
      expect(events.last.errorCode, MediaKitPlayer.kErrorCode);
      await subscription.cancel();
      await adapter.release();
    }
  });

  test(
      'atempo native fatal errors stop even though media_kit does not promote them',
      () async {
    final native = _NativeEvents();
    final adapter = MediaKitPlayer.withPlayer('atempo',
        Player(platformPlayer: native), MediaKitSpeedProcessor.atempo);
    final events = <PlaybackEventMessage>[];
    final subscription = adapter.playbackEventMessageStream.listen(events.add);
    native.log('lavfi_tempo', 'fatal', 'failed to create lavfi atempo filter.');
    await _deliverEvents();
    expect(native.stops, 1);
    expect(events.last.errorMessage, contains('atempo'));
    native.log(
        'af', 'error', 'Disabling filter crisper_speed because it has failed.');
    await _deliverEvents();
    expect(native.stops, 1, reason: 'Latch the first cause and stop only once');
    expect(events.last.errorMessage,
        contains('failed to create lavfi atempo filter'));
    await subscription.cancel();
    await adapter.release();
  });

  test('warnings, other filters and existing default processors are unaffected',
      () async {
    for (final engine in [
      MediaKitSpeedProcessor.automatic,
      MediaKitSpeedProcessor.legacyScaletempo,
      MediaKitSpeedProcessor.wsola
    ]) {
      final native = _NativeEvents();
      final adapter = MediaKitPlayer.withPlayer(
          'normal-${engine.name}', Player(platformPlayer: native), engine);
      native.log('crisperdsp', 'warn', 'A diagnostic warning');
      native.log('af', 'error',
          'Disabling filter an_unrelated_filter because it has failed.');
      native.log('file', 'error', 'Failed to open a different media file.');
      if (engine.audioFilter == null) {
        native.log('crisperdsp', 'error', 'Not the selected processor');
      }
      await _deliverEvents();
      expect(native.pauses, 0);
      expect(native.stops, 0);
      await adapter.release();
    }
  });

  test('failed native pause and stop release the player instead of continuing',
      () async {
    final native = _NativeEvents()..failPauseAndStop = true;
    final adapter = MediaKitPlayer.withPlayer('release',
        Player(platformPlayer: native), MediaKitSpeedProcessor.bungee);
    native.log('crisperdsp', 'error', 'DSP failed');
    await _deliverEvents();
    expect(native.pauses, 1);
    expect(native.stops, 1);
    expect(native.disposals, 1);
    await adapter.release();
    expect(native.disposals, 1);
  });
}
