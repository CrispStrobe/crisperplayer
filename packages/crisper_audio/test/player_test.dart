import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:crisper_audio/crisper_audio.dart';
import 'package:flutter_test/flutter_test.dart';

String writeWave(
  Directory directory,
  String name,
  List<int> samples, {
  int sampleRate = 16000,
  int channels = 1,
}) {
  final bytes = ByteData(44 + samples.length * 2);
  void tag(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes.setUint8(offset + i, value.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  bytes.setUint32(4, bytes.lengthInBytes - 8, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, channels, Endian.little);
  bytes.setUint32(24, sampleRate, Endian.little);
  bytes.setUint32(28, sampleRate * channels * 2, Endian.little);
  bytes.setUint16(32, channels * 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  bytes.setUint32(40, samples.length * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    bytes.setInt16(44 + i * 2, samples[i], Endian.little);
  }
  final file = File('${directory.path}/$name.wav');
  file.writeAsBytesSync(bytes.buffer.asUint8List());
  return file.path;
}

Future<int> drain(NativeAudioPlayer player) async {
  var count = 0;
  for (var i = 0; i < 5000; i++) {
    if (player.state == NativeAudioState.completed) return count;
    count += await player.pump(511);
  }
  fail('Playback did not drain');
}

void main() {
  final library = Platform.environment['CRISPER_AUDIO_LIBRARY_PATH'];
  if (Platform.environment['CRISPER_REQUIRE_NATIVE_AUDIO'] == '1' &&
      library == null) {
    throw StateError('Native CI requires CRISPER_AUDIO_LIBRARY_PATH');
  }
  final skip = library == null
      ? 'Set CRISPER_AUDIO_LIBRARY_PATH to the controlled native build'
      : false;
  late Directory directory;
  late String wave;
  late List<int> samples;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('crisper-player-test-');
    samples = List<int>.generate(12003, (i) => ((i * 197) % 30000) - 15000);
    wave = writeWave(directory, 'source', samples);
  });
  tearDown(() => directory.deleteSync(recursive: true));

  NativeAudioPlayer player({
    NativeSpeedEngine engine = NativeSpeedEngine.sonic,
    int bufferFrames = 512,
  }) {
    final player = NativeAudioPlayer(
      engine: engine,
      libraryPath: library,
      testOutput: true,
      bufferFrames: bufferFrames,
    );
    addTearDown(player.dispose);
    return player;
  }

  test(
    'PCM is bounded, underrun silence never advances the source clock',
    () async {
      final audio = player();
      await audio.load([wave]);
      expect(audio.position, Duration.zero);
      await audio.play();
      // Deliberately ask for more than the bounded native queue can hold.
      final block = await audio.renderForTest(2048);
      expect(block.consumedFrames, 512);
      expect(
        block.samples.take(512),
        orderedEquals(samples.take(512).map((x) => x / 32768)),
      );
      expect(block.samples.skip(512), everyElement(0));
      expect(audio.position, const Duration(milliseconds: 32));
      await Future<void>.delayed(const Duration(milliseconds: 40));
      // A running worker without output presentation cannot move media time.
      expect(audio.position, const Duration(milliseconds: 32));
    },
    skip: skip,
  );

  test(
    'pause preserves exact queued PCM and resume consumes its next frame',
    () async {
      final audio = player();
      await audio.load([wave]);
      await audio.play();
      expect(await audio.pump(137), 137);
      final position = audio.position;
      await audio.pause();
      final silent = await audio.renderForTest(900);
      expect(silent.consumedFrames, 0);
      expect(silent.samples, everyElement(0));
      expect(audio.position, position);
      await audio.play();
      final resumed = await audio.renderForTest(100);
      expect(
        resumed.samples,
        orderedEquals(samples.skip(137).take(100).map((x) => x / 32768)),
      );
    },
    skip: skip,
  );

  test(
    'seek drops queued audio and produces the exact requested source frame',
    () async {
      final audio = player();
      await audio.load([wave]);
      await audio.play();
      await audio.pump(77);
      await audio.seek(const Duration(milliseconds: 500));
      expect(audio.position, const Duration(milliseconds: 500));
      final seeked = await audio.renderForTest(100);
      expect(
        seeked.samples,
        orderedEquals(samples.skip(8000).take(100).map((x) => x / 32768)),
      );
    },
    skip: skip,
  );

  test(
    'rate reset uses played source time, not queued decoder read-ahead',
    () async {
      final audio = player();
      await audio.load([wave]);
      await audio.play();
      await audio.pump(160);
      expect(audio.position, const Duration(milliseconds: 10));
      await audio.setSpeed(2);
      expect(audio.position, const Duration(milliseconds: 10));
      final count = await drain(audio);
      expect(count, ((samples.length - 160) / 2).round());
      expect(audio.position, audio.duration);
      expect(audio.playing, isTrue);
    },
    skip: skip,
  );

  for (final engine in NativeSpeedEngine.values) {
    test(
      '${engine.name}: exact finite drain with non-block-aligned source',
      () async {
        final audio = player(engine: engine, bufferFrames: 1024);
        final sine = List<int>.generate(
          24003,
          (i) => (math.sin(i * 2 * math.pi * 440 / 16000) * 12000).round(),
        );
        final path = writeWave(directory, 'sine-${engine.name}', sine);
        await audio.setSpeed(1.5);
        await audio.load([path]);
        await audio.play();
        expect(await drain(audio), (sine.length / 1.5).round());
        expect(audio.position, audio.duration);
        expect(audio.state, NativeAudioState.completed);
        expect(audio.playing, isTrue);
        await audio.pause();
        expect(audio.playing, isFalse);
      },
      skip: skip,
    );
  }

  test(
    'automatic source advance reports old final position before new index',
    () async {
      final audio = player();
      final first = writeWave(directory, 'first', samples.take(533).toList());
      final second = writeWave(directory, 'second', samples.take(677).toList());
      final events = <NativeAudioSnapshot>[];
      final subscription = audio.snapshots.listen(events.add);
      addTearDown(subscription.cancel);
      await audio.load([first, second]);
      await audio.play();
      expect(await drain(audio), 533 + 677);
      expect(audio.index, 1);
      final completedOld = events.indexWhere(
        (s) =>
            s.index == 0 &&
            s.position == s.duration &&
            s.duration > Duration.zero,
      );
      final loadedNext = events.indexWhere((s) => s.index == 1);
      expect(completedOld, greaterThanOrEqualTo(0));
      expect(loadedNext, greaterThan(completedOld));
    },
    skip: skip,
  );

  test(
    'a newer load cancels the old request without surfacing a playback error',
    () async {
      final audio = player();
      final errors = <NativeAudioError>[];
      final subscription = audio.errors.listen(errors.add);
      addTearDown(subscription.cancel);
      final first = audio
          .load([wave])
          .then<Object?>((_) => null, onError: (Object e) => e);
      await audio.load([wave], position: const Duration(milliseconds: 100));
      expect(await first, isA<NativeAudioCancelled>());
      expect(audio.position, const Duration(milliseconds: 100));
      expect(errors, isEmpty);
    },
    skip: skip,
  );

  test(
    'decoder failure persists once and a new load explicitly recovers',
    () async {
      final audio = player();
      final errors = <NativeAudioError>[];
      final subscription = audio.errors.listen(errors.add);
      addTearDown(subscription.cancel);
      await expectLater(
        audio.load(['${directory.path}/missing.wav']),
        throwsA(isA<NativeAudioError>()),
      );
      final failure = audio.snapshot.error!.message;
      await expectLater(audio.play(), throwsA(isA<NativeAudioError>()));
      expect(audio.snapshot.error!.message, failure);
      expect(errors, hasLength(1));
      expect(audio.playing, isFalse);
      await audio.load([wave]);
      expect(audio.snapshot.error, isNull);
      await audio.play();
      expect(await audio.pump(42), 42);
    },
    skip: skip,
  );

  test('stop interrupts a header scan through the shared atomic token', () async {
    // A valid repeated frame header makes indexing substantial, but no encoded
    // payload is decoded: cancellation must finish before native decode starts.
    final file = File('${directory.path}/long.mp3');
    const frameBytes = 417; // MPEG1 layer III, 128 kbit/s, 44.1 kHz.
    final chunk = Uint8List(frameBytes * 1024);
    for (var i = 0; i < 1024; i++) {
      chunk.setRange(i * frameBytes, i * frameBytes + 4, [
        0xff,
        0xfb,
        0x90,
        0xc4,
      ]);
    }
    final output = file.openSync(mode: FileMode.write);
    try {
      for (var i = 0; i < 256; i++) {
        output.writeFromSync(chunk);
      }
    } finally {
      output.closeSync();
    }
    final audio = player();
    final errors = <NativeAudioError>[];
    final subscription = audio.errors.listen(errors.add);
    addTearDown(subscription.cancel);
    final loading = audio.snapshots.firstWhere(
      (s) => s.state == NativeAudioState.loading,
    );
    final pending = audio
        .load([file.path])
        .then<Object?>((_) => null, onError: (Object e) => e);
    await loading.timeout(const Duration(seconds: 5));
    await audio.stop().timeout(const Duration(seconds: 5));
    expect(await pending, isA<NativeAudioCancelled>());
    expect(audio.state, NativeAudioState.idle);
    expect(errors, isEmpty);
    // A subsequent source can open and play, proving cancellation did not poison
    // the worker's first-error latch or leave the old device/session active.
    await audio.load([wave]);
    await audio.play();
    expect(await audio.pump(17), 17);
  }, skip: skip);

  test(
    'rate changes preserve a non-microsecond-aligned presented frame',
    () async {
      final audio = player();
      final path = writeWave(
        directory,
        'fractional-clock',
        samples,
        sampleRate: 44100,
      );
      await audio.load([path]);
      await audio.play();
      await audio.pump(137);
      final position = audio.position;
      await audio.setSpeed(2);
      expect(audio.position, position);
      await audio.setSpeed(1);
      final captured = await audio.renderForTest(1);
      expect(captured.samples.single, samples[137] / 32768);
    },
    skip: skip,
  );

  test(
    'probe and waveform share decoder duration and bounded PCM reads',
    () async {
      final metadata = await NativeAudioProbe.probe(wave, libraryPath: library);
      expect(metadata.totalFrames, samples.length);
      expect(metadata.sampleRate, 16000);
      expect(metadata.channels, 1);
      expect(metadata.format, 'wav');
      final waveform = await NativeAudioProbe.waveform(
        wave,
        bins: 19,
        libraryPath: library,
      );
      expect(waveform.peaks, hasLength(19));
      final expected = List<double>.filled(19, 0);
      for (var i = 0; i < samples.length; i++) {
        final bin = i * 19 ~/ samples.length;
        expected[bin] = math.max(expected[bin], samples[i].abs() / 32768);
      }
      expect(waveform.peaks, orderedEquals(expected));
      expect(waveform.metadata.duration, metadata.duration);
    },
    skip: skip,
  );

  test(
    'stop retains presented position and ordered dispose cancels pending work',
    () async {
      final audio = player();
      await audio.load([wave]);
      await audio.play();
      await audio.pump(160);
      await audio.stop();
      expect(audio.state, NativeAudioState.idle);
      expect(audio.position, const Duration(milliseconds: 10));
      await audio.play();
      final resumed = await audio.renderForTest(1);
      expect(resumed.samples.single, samples[160] / 32768);
      final pending = audio
          .load([wave])
          .then<Object?>((_) => null, onError: (Object e) => e);
      await audio.dispose();
      expect(await pending, isA<NativeAudioCancelled>());
      await expectLater(audio.play(), throwsStateError);
      await audio.dispose();
    },
    skip: skip,
  );
}
