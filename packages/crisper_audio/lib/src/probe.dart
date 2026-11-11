// SPDX-License-Identifier: MIT
import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:ffi/ffi.dart';
import 'decoder.dart';
import 'library.dart';
import 'types.dart';

/// Metadata and waveform extraction use the playback decoder, without opening
/// an output device or retaining a complete decoded recording in memory.
abstract final class NativeAudioProbe {
  static Future<NativeAudioMetadata> probe(
    String path, {
    String? libraryPath,
  }) => Isolate.run(() {
    final decoder = PcmDecoder.open(
      path,
      library: openNativeLibrary(path: libraryPath),
    );
    try {
      return _metadata(decoder);
    } finally {
      decoder.dispose();
    }
  });

  static Future<NativeAudioWaveform> waveform(
    String path, {
    int bins = 1000,
    String? libraryPath,
  }) {
    if (bins < 1 || bins > 100000) {
      throw RangeError.range(bins, 1, 100000, 'bins');
    }
    return Isolate.run(() async {
      final decoder = PcmDecoder.open(
        path,
        library: openNativeLibrary(path: libraryPath),
      );
      Pointer<Float> buffer = nullptr;
      try {
        final metadata = _metadata(decoder);
        const block = 4096;
        buffer = calloc<Float>(block * decoder.channels);
        final samples = buffer.asTypedList(block * decoder.channels);
        final peaks = List<double>.filled(bins, 0);
        var frameOffset = 0;
        final yieldBudget = Stopwatch()..start();
        while (true) {
          final count = decoder.readFrames(buffer, block);
          if (count == 0) break;
          for (var frame = 0; frame < count; frame++) {
            final bin = math.min(
              bins - 1,
              (frameOffset + frame) * bins ~/ math.max(1, metadata.totalFrames),
            );
            var peak = peaks[bin];
            for (var channel = 0; channel < decoder.channels; channel++) {
              final value = samples[frame * decoder.channels + channel].abs();
              if (!value.isFinite) {
                throw const FormatException('Non-finite decoded PCM');
              }
              peak = math.max(peak, math.min(1.0, value));
            }
            peaks[bin] = peak;
          }
          frameOffset += count;
          if (yieldBudget.elapsedMilliseconds >= 16) {
            await Future<void>.delayed(Duration.zero);
            yieldBudget.reset();
          }
        }
        if (frameOffset != metadata.totalFrames) {
          throw FormatException(
            'Decoded duration changed: $frameOffset/${metadata.totalFrames} frames',
          );
        }
        return NativeAudioWaveform(
          metadata: metadata,
          peaks: List<double>.unmodifiable(peaks),
        );
      } finally {
        if (buffer != nullptr) calloc.free(buffer);
        decoder.dispose();
      }
    });
  }

  static NativeAudioMetadata _metadata(PcmDecoder decoder) =>
      NativeAudioMetadata(
        sampleRate: decoder.sampleRate,
        channels: decoder.channels,
        totalFrames: decoder.totalFrames,
        format: decoder.format,
      );
}
