// SPDX-License-Identifier: MIT
import 'types.dart';

abstract final class NativeAudioProbe {
  static Future<NativeAudioMetadata> probe(
    String path, {
    String? libraryPath,
  }) async =>
      throw UnsupportedError('Native decoding requires a native platform');
  static Future<NativeAudioWaveform> waveform(
    String path, {
    int bins = 1000,
    String? libraryPath,
  }) async =>
      throw UnsupportedError('Native decoding requires a native platform');
}
