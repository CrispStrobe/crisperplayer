import 'package:crisperplayer/services/audio/speed_processing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';

/// Records the actual just_audio method-channel payload. Audio decoding is
/// simulated here; Apple CI separately compiles the patched native plugin.
class _NativeTransport {
  final requests = <Map<Object?, Object?>>[];
  final channels = <MethodChannel>[];
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  static const codec = StandardMethodCodec();

  void install() {
    _handle(
      const MethodChannel('com.ryanheise.audio_session'),
      (_) async => null,
    );
    _handle(const MethodChannel('com.ryanheise.just_audio.methods'), (
      call,
    ) async {
      if (call.method == 'init') {
        final request = Map<Object?, Object?>.from(call.arguments as Map);
        requests.add(request);
        final id = request['id']! as String;
        _handle(
          MethodChannel('com.ryanheise.just_audio.events.$id'),
          (_) async => null,
        );
        _handle(
          MethodChannel('com.ryanheise.just_audio.data.$id'),
          (_) async => null,
        );
        _handle(MethodChannel('com.ryanheise.just_audio.methods.$id'), (
          call,
        ) async {
          if (call.method == 'load') {
            await messenger.handlePlatformMessage(
              'com.ryanheise.just_audio.events.$id',
              codec.encodeSuccessEnvelope({
                'processingState': 3,
                'updateTime': DateTime.now().millisecondsSinceEpoch,
                'updatePosition': 0,
                'bufferedPosition': 120000000,
                'duration': 120000000,
                'currentIndex': 0,
              }),
              null,
            );
            return {'duration': 120000000};
          }
          return <String, Object?>{};
        });
      }
      return <String, Object?>{};
    });
  }

  void _handle(
    MethodChannel channel,
    Future<Object?> Function(MethodCall) handler,
  ) {
    channels.add(channel);
    messenger.setMockMethodCallHandler(channel, handler);
  }

  void close() {
    for (final channel in channels) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final mode in DarwinTimePitchAlgorithm.values) {
    test(
      'native init transports $mode and retains it after player recreation',
      () async {
        final transport = _NativeTransport()..install();
        final player = AudioPlayer(
          handleInterruptions: false,
          androidApplyAudioAttributes: false,
          handleAudioSessionActivation: false,
          audioLoadConfiguration: AudioLoadConfiguration(
            darwinLoadControl: DarwinLoadControl(
              audioTimePitchAlgorithm: mode,
              automaticallyWaitsToMinimizeStalling: false,
              preferredForwardBufferDuration: const Duration(seconds: 7),
              preferredPeakBitRate: 123000,
              canUseNetworkResourcesForLiveStreamingWhilePaused: true,
            ),
          ),
        );
        try {
          await player.setAudioSources([
            AudioSource.uri(Uri.file('/fixture-a.wav')),
          ]);
          await player.setSpeed(1.5);
          await player.stop();
          await player.setAudioSources([
            AudioSource.uri(Uri.file('/fixture-b.wav')),
          ]);
          expect(transport.requests, hasLength(2));
          for (final request in transport.requests) {
            final configuration = request['audioLoadConfiguration']! as Map;
            expect(configuration['darwinLoadControl'], {
              'automaticallyWaitsToMinimizeStalling': false,
              'preferredForwardBufferDuration': 7000000,
              'canUseNetworkResourcesForLiveStreamingWhilePaused': true,
              'preferredPeakBitRate': 123000.0,
              'audioTimePitchAlgorithm': mode.name,
            });
            expect(configuration['androidLoadControl'], isNull);
            expect(configuration['androidLivePlaybackSpeedControl'], isNull);
          }
          expect(player.speed, 1.5);
        } finally {
          await player.dispose();
          transport.close();
        }
      },
    );
  }

  test(
    'upstream default remains Time Domain and non-Apple startup stays unchanged',
    () async {
      expect(
        const DarwinLoadControl().audioTimePitchAlgorithm,
        DarwinTimePitchAlgorithm.timeDomain,
      );
      final transport = _NativeTransport()..install();
      final previous = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final player = AudioPlayer(
        handleInterruptions: false,
        androidApplyAudioAttributes: false,
        handleAudioSessionActivation: false,
        audioLoadConfiguration: SpeedProcessing.appleLoadConfiguration,
      );
      try {
        expect(SpeedProcessing.appleLoadConfiguration, isNull);
        await player.setAudioSources([
          AudioSource.uri(Uri.file('/fixture.wav')),
        ]);
        expect(transport.requests.single['audioLoadConfiguration'], isNull);
        await player.setSpeed(2);
        expect(player.speed, 2);
      } finally {
        await player.dispose();
        transport.close();
        debugDefaultTargetPlatformOverride = previous;
      }
    },
  );
}
