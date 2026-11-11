import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crisper_audio/src/decoder.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

String fixture(String name) {
  final local = File('test/fixtures/$name');
  if (local.existsSync()) return local.path;
  return 'packages/crisper_audio/test/fixtures/$name';
}

Uint8List waveBytes(
  List<num> values, {
  int bits = 16,
  int channels = 1,
  bool floating = false,
  bool extensible = false,
}) {
  final formatBytes = extensible ? 40 : 16;
  final dataAt = 28 + formatBytes;
  final samplesBytes = values.length * (bits ~/ 8);
  final bytes = Uint8List(dataAt + samplesBytes + (samplesBytes & 1));
  final b = ByteData.sublistView(bytes);
  void text(int at, String text) =>
      bytes.setRange(at, at + text.length, text.codeUnits);
  text(0, 'RIFF');
  b.setUint32(4, bytes.length - 8, Endian.little);
  text(8, 'WAVE');
  text(12, 'fmt ');
  b.setUint32(16, formatBytes, Endian.little);
  b.setUint16(20, extensible ? 0xfffe : (floating ? 3 : 1), Endian.little);
  b.setUint16(22, channels, Endian.little);
  b.setUint32(24, 44100, Endian.little);
  b.setUint32(28, 44100 * channels * bits ~/ 8, Endian.little);
  b.setUint16(32, channels * bits ~/ 8, Endian.little);
  b.setUint16(34, bits, Endian.little);
  if (extensible) {
    b.setUint16(36, 22, Endian.little);
    b.setUint16(38, bits, Endian.little);
    b.setUint32(40, channels == 1 ? 4 : 3, Endian.little);
    bytes.setRange(44, 60, [
      floating ? 3 : 1,
      0,
      0,
      0,
      0,
      0,
      0x10,
      0,
      0x80,
      0,
      0,
      0xaa,
      0,
      0x38,
      0x9b,
      0x71,
    ]);
  }
  text(dataAt - 8, 'data');
  b.setUint32(dataAt - 4, samplesBytes, Endian.little);
  for (var i = 0; i < values.length; i++) {
    final at = dataAt + i * bits ~/ 8;
    if (floating) {
      if (bits == 32) {
        b.setFloat32(at, values[i].toDouble(), Endian.little);
      } else {
        b.setFloat64(at, values[i].toDouble(), Endian.little);
      }
    } else {
      final value = values[i].toInt();
      for (var j = 0; j < bits ~/ 8; j++) {
        bytes[at + j] = (value >> (8 * j)) & 255;
      }
    }
  }
  return bytes;
}

int flacCrc(List<int> bytes, int width, int polynomial) {
  var crc = 0;
  final mask = (1 << width) - 1;
  for (final byte in bytes) {
    crc ^= byte << (width - 8);
    for (var bit = 0; bit < 8; bit++) {
      crc =
          ((crc << 1) ^ ((crc & (1 << (width - 1))) != 0 ? polynomial : 0)) &
          mask;
    }
  }
  return crc;
}

List<int> flacNumber(int number) {
  if (number < 128) return [number];
  var extra = 1;
  while (number >= (1 << (5 * extra + 6))) {
    extra++;
  }
  return [
    ((0xff << (7 - extra)) & 0xff) | (number >> (6 * extra)),
    for (var i = extra - 1; i >= 0; i--) 0x80 | ((number >> (6 * i)) & 63),
  ];
}

int flacRamp(int frame, int channel) =>
    (frame * 13 + channel * 997) % 32768 - 16384;

/// Independently constructed valid verbatim FLAC, larger than the decoder's
/// compressed window. Variable blocking carries PCM sample numbers in headers.
void writeLargeFlac(File file) {
  const block = 65535;
  const count = 9;
  final metadata = Uint8List(42);
  metadata.setAll(0, [102, 76, 97, 67, 0x80, 0, 0, 34]);
  final m = ByteData.sublistView(metadata);
  m.setUint16(8, block);
  m.setUint16(10, block);
  m.setUint64(18, (44100 << 44) | (1 << 41) | (15 << 36) | (block * count));
  final out = file.openSync(mode: FileMode.write);
  try {
    out.writeFromSync(metadata);
    for (var frame = 0; frame < count; frame++) {
      final header = <int>[
        0xff,
        0xf9,
        0x70,
        0x18,
        ...flacNumber(frame * block),
        0xff,
        0xfe,
      ];
      header.add(flacCrc(header, 8, 7));
      final bytes = Uint8List(header.length + 2 * (1 + block * 2) + 2);
      bytes.setAll(0, header);
      final b = ByteData.sublistView(bytes);
      var at = header.length;
      for (var ch = 0; ch < 2; ch++) {
        bytes[at++] = 2; // Verbatim, no wasted bits.
        for (var i = 0; i < block; i++) {
          b.setInt16(at, flacRamp(frame * block + i, ch));
          at += 2;
        }
      }
      b.setUint16(at, flacCrc(Uint8List.sublistView(bytes, 0, at), 16, 0x8005));
      out.writeFromSync(bytes);
    }
  } finally {
    out.closeSync();
  }
}

void main() {
  final libraryPath = Platform.environment['CRISPER_AUDIO_LIBRARY_PATH'];
  if (Platform.environment['CRISPER_REQUIRE_NATIVE_AUDIO'] == '1' &&
      (libraryPath == null ||
          libraryPath.isEmpty ||
          !File(libraryPath).existsSync())) {
    throw StateError(
      'Native decoder tests are required: set '
      'CRISPER_AUDIO_LIBRARY_PATH to the freshly built shared library',
    );
  }
  late Directory tmp;
  late Pointer<Float> output;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('crisper-decoder-');
    output = calloc<Float>(8192);
  });
  tearDown(() {
    calloc.free(output);
    tmp.deleteSync(recursive: true);
  });

  test(
    'PCM WAV is bounded, frame-counted, seekable and independent of native codecs',
    () {
      final samples = List<int>.generate(
        12000,
        (i) => (i * 997) % 65536 - 32768,
      );
      final file = File('${tmp.path}/pcm.wav')
        ..writeAsBytesSync(waveBytes(samples, channels: 2));
      final decoder = PcmDecoder.open(file.path);
      try {
        expect(decoder.format, 'wav');
        expect(decoder.sampleRate, 44100);
        expect(decoder.channels, 2);
        expect(decoder.totalFrames, 6000);
        expect(decoder.readFrames(output, 9000), 4096);
        expect(decoder.positionFrames, 4096);
        decoder.seek(17);
        expect(decoder.readFrames(output, 3), 3);
        expect(
          output.asTypedList(6),
          orderedEquals(samples.skip(34).take(6).map((v) => v / 32768)),
        );
        decoder.seek(5999);
        expect(decoder.readFrames(output, 40), 1);
        expect(decoder.readFrames(output, 40), 0);
        decoder.seek(900000);
        expect(decoder.positionFrames, 6000);
        expect(() => decoder.seek(-1), throwsRangeError);
        expect(() => decoder.readFrames(output, -1), throwsRangeError);
      } finally {
        decoder.dispose();
      }
      decoder.dispose();
      expect(() => decoder.readFrames(output, 1), throwsStateError);
    },
  );

  for (final bits in [8, 16, 24, 32]) {
    test('PCM $bits-bit WAV conversion handles signed edges', () {
      final scale = 1 << (bits - 1);
      final values = bits == 8 ? [0, 128, 255] : [-scale, 0, scale - 1];
      final file = File('${tmp.path}/pcm.wav')
        ..writeAsBytesSync(waveBytes(values, bits: bits));
      final decoder = PcmDecoder.open(file.path);
      try {
        expect(decoder.readFrames(output, 20), 3);
        expect(output[0], -1);
        expect(output[1], 0);
        expect(output[2], closeTo((scale - 1) / scale, 1e-7));
      } finally {
        decoder.dispose();
      }
    });
  }

  for (final bits in [32, 64]) {
    test(
      'Extensible float $bits-bit WAV is decoded without integer conversion',
      () {
        final file = File('${tmp.path}/float.wav')
          ..writeAsBytesSync(
            waveBytes(
              [-0.75, 0.125, 0.5, -0.25],
              bits: bits,
              channels: 2,
              floating: true,
              extensible: true,
            ),
          );
        final decoder = PcmDecoder.open(file.path);
        try {
          expect(decoder.readFrames(output, 20), 2);
          expect(
            output.asTypedList(4),
            orderedEquals([-0.75, 0.125, 0.5, -0.25]),
          );
        } finally {
          decoder.dispose();
        }
      },
    );
  }

  test('WAV corrupt payload and non-finite samples fail and latch', () {
    final invalid = waveBytes([0, 1]);
    ByteData.sublistView(invalid).setUint32(40, 0xffffffff, Endian.little);
    final file = File('${tmp.path}/bad.wav')..writeAsBytesSync(invalid);
    expect(() => PcmDecoder.open(file.path), throwsFormatException);
    file.writeAsBytesSync(waveBytes([double.nan], bits: 32, floating: true));
    final decoder = PcmDecoder.open(file.path);
    try {
      expect(() => decoder.readFrames(output, 1), throwsFormatException);
      expect(() => decoder.seek(0), throwsStateError);
    } finally {
      decoder.dispose();
    }
  });

  test(
    'Opening WAV and header-scanning MP3 cooperatively cancel and close files',
    () {
      final cancelled = StateError('test cancellation');
      final wav = File('${tmp.path}/cancel.wav')
        ..writeAsBytesSync(waveBytes([0, 1]));
      var calls = 0;
      expect(
        () => PcmDecoder.open(
          wav.path,
          checkCancelled: () {
            if (++calls == 4) throw cancelled;
          },
        ),
        throwsA(same(cancelled)),
      );
      calls = 0;
      expect(
        () => PcmDecoder.open(
          fixture('stereo_vbr.mp3'),
          checkCancelled: () {
            if (++calls == 30) throw cancelled;
          },
        ),
        throwsA(same(cancelled)),
      );
      expect(calls, 30);
      // A failed open owns no native decoder and leaves the source removable.
      wav.deleteSync();
    },
  );

  test('Unsupported containers and truncated ID3 do not guess a codec', () {
    final unknown = File('${tmp.path}/audio.flac')
      ..writeAsBytesSync(Uint8List.fromList('fLaC------------'.codeUnits));
    expect(() => PcmDecoder.open(unknown.path), throwsFormatException);
    unknown.writeAsBytesSync([73, 68, 51, 4, 0, 0, 0, 0, 20, 0, 0, 0]);
    expect(() => PcmDecoder.open(unknown.path), throwsFormatException);
  });

  final skipNative = libraryPath == null
      ? 'Set CRISPER_AUDIO_LIBRARY_PATH to run real Glint decoder regressions'
      : false;
  final cases = [
    ('stereo_vbr.mp3', 'mp3', 44100, 2),
    ('mono_mpeg2.mp3', 'mp3', 22050, 1),
    ('mono_mpeg25.mp3', 'mp3', 11025, 1),
    ('stereo_lc.aac', 'aac-adts', 44100, 2),
    ('stereo_lc.m4b', 'aac-mp4', 44100, 2),
    ('stereo_pcm16.flac', 'flac', 44100, 2),
    ('stereo_pcm24.flac', 'flac', 44100, 2),
  ];
  for (final c in cases) {
    test(
      '${c.$1} exact duration, partial reads, packet-boundary and tail seeks',
      () {
        final decoder = PcmDecoder.open(
          fixture(c.$1),
          library: DynamicLibrary.open(libraryPath!),
        );
        try {
          expect(decoder.format, c.$2);
          expect(decoder.sampleRate, c.$3);
          expect(decoder.channels, c.$4);
          if (c.$2 == 'aac-adts') {
            expect(
              decoder.totalFrames,
              inInclusiveRange(c.$3 * 4, c.$3 * 4 + 2048),
            );
          } else {
            expect(decoder.totalFrames, c.$3 * 4);
          }
          final reference = Float32List(decoder.totalFrames * decoder.channels);
          var read = 0;
          while (true) {
            final n = decoder.readFrames(output, 997);
            if (n == 0) break;
            expect(n, inInclusiveRange(1, 997));
            reference.setRange(
              read * decoder.channels,
              (read + n) * decoder.channels,
              output.asTypedList(n * decoder.channels),
            );
            read += n;
            expect(decoder.positionFrames, read);
          }
          expect(read, decoder.totalFrames);
          expect(reference.every((v) => v.isFinite), isTrue);
          expect(reference.any((v) => v.abs() > 0.02), isTrue);
          for (final at in [
            0,
            1,
            575,
            1023,
            1024,
            1151,
            73113,
            decoder.totalFrames - 101,
            decoder.totalFrames - 1,
          ]) {
            if (at >= decoder.totalFrames) continue;
            decoder.seek(at);
            expect(decoder.positionFrames, at);
            final n = decoder.readFrames(output, 211);
            final actual = output.asTypedList(n * decoder.channels);
            for (var i = 0; i < actual.length; i++) {
              expect(
                actual[i],
                closeTo(reference[at * decoder.channels + i], 1e-6),
                reason: '${c.$1}: seek frame $at, scalar $i',
              );
            }
          }
          decoder.seek(decoder.totalFrames);
          expect(decoder.readFrames(output, 10), 0);
        } finally {
          decoder.dispose();
        }
      },
      skip: skipNative,
    );
  }

  for (final bits in [16, 24]) {
    test('FLAC $bits-bit PCM matches every original sample exactly', () {
      final decoder = PcmDecoder.open(
        fixture('stereo_pcm$bits.flac'),
        library: DynamicLibrary.open(libraryPath!),
      );
      try {
        var position = 0;
        while (true) {
          final n = decoder.readFrames(output, 4096);
          if (n == 0) break;
          final samples = output.asTypedList(n * 2);
          for (var j = 0; j < n; j++) {
            final i = position + j;
            var left = (i * 17 % 20000) - 10000;
            var right = ((i * 31 + 741) % 24000) - 12000;
            if (bits == 24) {
              left = left * 127 + i % 127;
              right = right * 173 - i % 173;
            }
            final scale = (1 << (bits - 1)).toDouble();
            if (samples[j * 2] != left / scale ||
                samples[j * 2 + 1] != right / scale) {
              fail('FLAC $bits-bit differs from source at frame $i');
            }
          }
          position += n;
        }
        expect(position, 176400);
      } finally {
        decoder.dispose();
      }
    }, skip: skipNative);
  }

  test('FLAC CRC corruption and unknown duration fail explicitly', () {
    final original = File(fixture('stereo_pcm16.flac')).readAsBytesSync();
    final file = File('${tmp.path}/corrupt.flac')..writeAsBytesSync(original);
    final changed = Uint8List.fromList(original);
    changed[changed.length - 1] ^= 0x55;
    file.writeAsBytesSync(changed);
    final decoder = PcmDecoder.open(
      file.path,
      library: DynamicLibrary.open(libraryPath!),
    );
    try {
      expect(
        () => decoder.seek(decoder.totalFrames - 1),
        throwsFormatException,
      );
      expect(() => decoder.readFrames(output, 1), throwsStateError);
    } finally {
      decoder.dispose();
    }
    changed.setAll(0, original);
    changed[8 + 13] &= 0xf0;
    changed.fillRange(8 + 14, 8 + 18, 0);
    file.writeAsBytesSync(changed);
    expect(
      () => PcmDecoder.open(
        file.path,
        library: DynamicLibrary.open(libraryPath),
      ),
      throwsFormatException,
    );
  }, skip: skipNative);

  test(
    'FLAC seek cooperatively cancels between bounded scan blocks',
    () {
      var calls = 0;
      var cancel = false;
      final cancelled = StateError('cancel FLAC seek');
      final decoder = PcmDecoder.open(
        fixture('stereo_pcm16.flac'),
        library: DynamicLibrary.open(libraryPath!),
        checkCancelled: () {
          if (cancel && ++calls >= 5) throw cancelled;
        },
      );
      try {
        cancel = true;
        expect(() => decoder.seek(140000), throwsA(same(cancelled)));
      } finally {
        decoder.dispose();
      }
    },
    skip: skipNative,
  );

  test(
    'Variable-block FLAC crosses the 2 MiB window and seeks without PCM indexing',
    () {
      final file = File('${tmp.path}/large.flac');
      writeLargeFlac(file);
      expect(file.lengthSync(), greaterThan(2 * 1024 * 1024));
      final decoder = PcmDecoder.open(
        file.path,
        library: DynamicLibrary.open(libraryPath!),
      );
      try {
        var position = 0;
        while (true) {
          final n = decoder.readFrames(output, 4096);
          if (n == 0) break;
          final samples = output.asTypedList(n * 2);
          for (var i = 0; i < n; i++) {
            if (samples[i * 2] != flacRamp(position + i, 0) / 32768 ||
                samples[i * 2 + 1] != flacRamp(position + i, 1) / 32768) {
              fail('FLAC window-boundary decode differs at ${position + i}');
            }
          }
          position += n;
        }
        expect(position, 65535 * 9);
        for (final at in [
          0,
          1,
          65534,
          65535,
          456789,
          decoder.totalFrames - 5,
        ]) {
          decoder.seek(at);
          final n = decoder.readFrames(output, 37);
          for (var i = 0; i < n; i++) {
            expect(output[i * 2], flacRamp(at + i, 0) / 32768);
            expect(output[i * 2 + 1], flacRamp(at + i, 1) / 32768);
          }
        }
      } finally {
        decoder.dispose();
      }
    },
    skip: skipNative,
  );

  test(
    'AAC-LC M4B preserves source timing, tone pitch and reference signal quality',
    () {
      final decoder = PcmDecoder.open(
        fixture('stereo_lc.m4b'),
        library: DynamicLibrary.open(libraryPath!),
      );
      try {
        var position = 0;
        var signal = 0.0;
        var error = 0.0;
        const frequencies = [730.0, 740.0, 750.0, 1250.0, 1260.0, 1270.0];
        final real = List<double>.filled(6, 0);
        final imaginary = List<double>.filled(6, 0);
        while (true) {
          final n = decoder.readFrames(output, 4096);
          if (n == 0) break;
          for (var i = 0; i < n; i++) {
            final t = (position + i) / 44100.0;
            final envelope = 0.55 + 0.35 * math.sin(2 * math.pi * 1.7 * t);
            final left =
                envelope *
                (0.20 * math.sin(2 * math.pi * (300 * t + 300 * t * t)) +
                    0.15 * math.sin(2 * math.pi * 740 * t));
            final right =
                envelope *
                (0.19 * math.sin(2 * math.pi * (431 * t + 93 * t * t)) +
                    0.14 * math.sin(2 * math.pi * 1260 * t));
            signal += left * left + right * right;
            error +=
                math.pow(output[i * 2] - left, 2) +
                math.pow(output[i * 2 + 1] - right, 2);
            for (var f = 0; f < frequencies.length; f++) {
              final sample = output[i * 2 + (f < 3 ? 0 : 1)];
              final phase = 2 * math.pi * frequencies[f] * t;
              real[f] += sample * math.cos(phase);
              imaginary[f] += sample * math.sin(phase);
            }
          }
          position += n;
        }
        final snrDb = 10 * math.log(signal / error) / math.ln10;
        // The source includes +/-0.004 random noise omitted from this analytic
        // reference. This is a timing/fidelity regression, not a general codec
        // quality claim or a comparison to lossless output.
        expect(
          snrDb,
          greaterThan(10),
          reason: 'AAC source-aligned SNR: $snrDb dB',
        );
        final power = List<double>.generate(
          6,
          (i) => real[i] * real[i] + imaginary[i] * imaginary[i],
        );
        expect(power[1], greaterThan(5 * math.max(power[0], power[2])));
        expect(power[4], greaterThan(5 * math.max(power[3], power[5])));
        expect(position, 176400);
        // Prints one reproducible measurement for CI evidence.
        // ignore: avoid_print
        print(
          'AAC-LC M4B: $position frames; analytic-source SNR '
          '${snrDb.toStringAsFixed(2)} dB; 740/1260 Hz tones retained',
        );
      } finally {
        decoder.dispose();
      }
    },
    skip: skipNative,
  );

  test(
    'AAC corruption throws, cannot masquerade as EOF, and failure stays latched',
    () {
      final data = File(fixture('stereo_lc.aac')).readAsBytesSync();
      final size = ((data[3] & 3) << 11) | (data[4] << 3) | (data[5] >> 5);
      data.fillRange(
        7,
        size,
        0,
      ); // Header intact; impossible/incomplete channel block.
      final file = File('${tmp.path}/broken.aac')..writeAsBytesSync(data);
      final decoder = PcmDecoder.open(
        file.path,
        library: DynamicLibrary.open(libraryPath!),
      );
      try {
        expect(() => decoder.readFrames(output, 20), throwsFormatException);
        expect(() => decoder.readFrames(output, 20), throwsStateError);
      } finally {
        decoder.dispose();
      }
    },
    skip: skipNative,
  );
}
