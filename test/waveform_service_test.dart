import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:crisperplayer/services/audio/waveform_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/audio_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('crisper_wave_');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  test(
    'short native waveform headers are not treated as audio samples',
    () async {
      for (final flags in [0, 1]) {
        final stride = flags == 0 ? 4 : 2;
        final bytes = ByteData(20 + 4 * stride);
        bytes.setUint32(0, 1, Endian.little);
        bytes.setUint32(4, flags, Endian.little);
        bytes.setUint32(8, 16000, Endian.little);
        bytes.setUint32(12, 16000, Endian.little);
        bytes.setUint32(16, 4, Endian.little);
        for (var index = 0; index < 4; index++) {
          if (flags == 0) {
            bytes.setInt16(20 + index * stride, -8192, Endian.little);
            bytes.setInt16(22 + index * stride, 16384, Endian.little);
          } else {
            bytes.setInt8(20 + index * stride, -32);
            bytes.setInt8(21 + index * stride, 64);
          }
        }
        final file = File('${root.path}/short-$flags.wave');
        await file.writeAsBytes(bytes.buffer.asUint8List());
        final waveform = await readNativeWaveform(file);
        expect(waveform.peaks, [.5, .5, .5, .5]);
        expect(waveform.duration, const Duration(seconds: 4));
        await file.writeAsBytes(bytes.buffer.asUint8List().sublist(0, 21));
        await expectLater(readNativeWaveform(file), throwsFormatException);
      }
    },
  );
  test(
    'real PCM peaks preserve silence and amplitude, with bounded output',
    () async {
      final file = await writeTestWav(
        File('${root.path}/tone.wav'),
        seconds: 2,
      );
      final bytes = await file.readAsBytes();
      bytes.fillRange(44, 44 + (bytes.length - 44) ~/ 2, 0);
      await file.writeAsBytes(bytes);
      final service = WaveformService(
        cacheDirectory: () async => Directory('${root.path}/cache'),
      );
      final waveform = await service.generate(
        file.path,
        const Duration(seconds: 2),
      );
      expect(waveform.duration, const Duration(seconds: 2));
      expect(waveform.peaks, hasLength(512));
      expect(waveform.peaks.take(250), everyElement(0));
      expect(
        waveform.peaks.skip(260),
        everyElement(inInclusiveRange(.030, .031)),
      );
      expect((await service.cached(file.path))!.peaks, waveform.peaks);
      service.dispose();
    },
  );
  test('PCM sample formats have correct full-scale amplitudes', () async {
    for (final bits in [8, 16, 24, 32]) {
      final source = await writeTestWav(
        File('${root.path}/$bits.wav'),
        seconds: 1,
      );
      final original = await source.readAsBytes();
      final width = bits ~/ 8, frames = 800;
      final data = ByteData(44 + frames * width);
      data.buffer.asUint8List().setRange(0, 44, original);
      data.setUint32(4, data.lengthInBytes - 8, Endian.little);
      data.setUint32(24, 8000, Endian.little);
      data.setUint32(28, 8000 * width, Endian.little);
      data.setUint16(32, width, Endian.little);
      data.setUint16(34, bits, Endian.little);
      data.setUint32(40, frames * width, Endian.little);
      for (var i = 0; i < frames; i++) {
        final at = 44 + i * width;
        if (bits == 8) {
          data.setUint8(at, 0);
        } else if (bits == 16) {
          data.setInt16(at, -32768, Endian.little);
        } else if (bits == 24) {
          data.setUint8(at + 2, 128);
        } else {
          data.setInt32(at, -2147483648, Endian.little);
        }
      }
      await source.writeAsBytes(data.buffer.asUint8List());
      final result = await extractPcmWave(source, (_) {});
      expect(result!.peaks, everyElement(1));
      expect(result.duration, const Duration(milliseconds: 100));
    }
  });
  test(
    'deduplicates decodes, invalidates changed sources, recovers corrupt cache',
    () async {
      final file = await writeTestWav(File('${root.path}/tone.wav'));
      final gate = Completer<void>();
      var calls = 0;
      final service = WaveformService(
        cacheDirectory: () async => Directory('${root.path}/cache'),
        extractor: (path, duration, progress) async {
          calls++;
          await gate.future;
          return const AudioWaveform([.25, .5], Duration(seconds: 12));
        },
      );
      final a = service.generate(file.path, const Duration(seconds: 12));
      final b = service.generate(file.path, const Duration(seconds: 12));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      gate.complete();
      expect(await a, same(await b));
      expect(calls, 1);
      await file.setLastModified(
        (await file.lastModified()).add(const Duration(seconds: 2)),
      );
      expect(await service.cached(file.path), isNull);
      await service.generate(file.path, const Duration(seconds: 12));
      expect(calls, 2);
      final cache = (await Directory(
        '${root.path}/cache',
      ).list().toList()).whereType<File>().last;
      // Corrupt every revision to avoid depending on directory enumeration order.
      for (final entry in await cache.parent.list().toList()) {
        if (entry is File) await entry.writeAsString('{broken');
      }
      expect(await service.cached(file.path), isNull);
      await service.generate(file.path, const Duration(seconds: 12));
      expect(calls, 3);
      service.dispose();
    },
  );
  test('failed extraction does not poison the next generation', () async {
    final file = await writeTestWav(File('${root.path}/tone.wav'));
    var calls = 0;
    final service = WaveformService(
      cacheDirectory: () async => Directory('${root.path}/cache'),
      extractor: (path, duration, progress) async {
        if (++calls == 1) throw const FormatException('decoder failed');
        return const AudioWaveform([.5], Duration(seconds: 12));
      },
    );
    await expectLater(
      service.generate(file.path, const Duration(seconds: 12)),
      throwsFormatException,
    );
    expect(await service.cached(file.path), isNull);
    expect(
      (await service.generate(file.path, const Duration(seconds: 12))).peaks,
      [.5],
    );
    service.dispose();
  });
  test('truncated input and invalid cached amplitudes are rejected', () async {
    final file = await writeTestWav(File('${root.path}/bad.wav'));
    final bytes = await file.readAsBytes();
    await file.writeAsBytes(bytes.sublist(0, 60));
    await expectLater(extractPcmWave(file, (_) {}), throwsFormatException);
    expect(
      () => AudioWaveform.fromJson({
        'peaks': [double.nan],
        'durationMs': 1000,
      }),
      throwsFormatException,
    );
  });
}
