import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:crisperplayer/services/audio/waveform_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final fixtureData = Platform.environment['CRISPER_WAVEFORM_BASE64'];
  testWidgets(
    'native compressed-audio waveform is cached without interrupting playback',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'crisper_native_wave_',
      );
      final fixture = File('${root.path}/tone.m4a');
      await fixture.writeAsBytes(base64Decode(fixtureData!));
      final service = WaveformService(cacheDirectory: () async => root);
      final player = AudioPlayer(handleInterruptions: false);
      try {
        await player.setVolume(0);
        final duration = await player.setFilePath(fixture.path);
        await player.setSpeed(1.5);
        await player.seek(const Duration(milliseconds: 1000));
        unawaited(player.play());
        final data = await service
            .generate(fixture.path, duration!)
            .timeout(const Duration(seconds: 45));
        expect(data.peaks, isNotEmpty);
        expect(data.peaks.length, lessThanOrEqualTo(512));
        expect(data.peaks.any((peak) => peak > .01), isTrue);
        expect(
          data.duration.inMilliseconds,
          closeTo(duration.inMilliseconds, 1100),
        );
        await Future<void>.delayed(const Duration(milliseconds: 400));
        expect(player.playing, isTrue);
        expect(player.speed, 1.5);
        expect(player.volume, 0);
        expect(player.position.inMilliseconds, greaterThan(1100));
        await player.pause();
        final reopened = WaveformService(cacheDirectory: () async => root);
        expect((await reopened.cached(fixture.path))!.peaks, data.peaks);
        reopened.dispose();
      } finally {
        await player.dispose();
        service.dispose();
        await root.delete(recursive: true);
      }
    },
    skip: fixtureData == null,
  );
}
