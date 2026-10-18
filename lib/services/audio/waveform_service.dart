import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show compute, ChangeNotifier;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Bounded display data, derived from decoded audio rather than synthetic bars.
class AudioWaveform {
  final List<double> peaks;
  final Duration duration;
  const AudioWaveform(this.peaks, this.duration);
  Map<String, Object> toJson() => {
    'peaks': peaks,
    'durationMs': duration.inMilliseconds,
  };
  factory AudioWaveform.fromJson(Map<String, dynamic> json) {
    final peaks = (json['peaks'] as List)
        .map((v) => (v as num).toDouble())
        .toList();
    if (peaks.isEmpty ||
        peaks.length > 512 ||
        peaks.any((v) => !v.isFinite || v < 0 || v > 1)) {
      throw const FormatException('Invalid waveform cache');
    }
    final duration = json['durationMs'] as int;
    if (duration <= 0) throw const FormatException('Invalid waveform duration');
    return AudioWaveform(
      List.unmodifiable(peaks),
      Duration(milliseconds: duration),
    );
  }
}

typedef WaveformExtractor =
    Future<AudioWaveform> Function(
      String path,
      Duration duration,
      void Function(double) onProgress,
    );

class WaveformService extends ChangeNotifier {
  static final shared = WaveformService();
  static final _nativeProgress = <String, void Function(double)>{};
  static final _nativeChannel =
      const MethodChannel('com.ryanheise.just_waveform')
        ..setMethodCallHandler((call) async {
          if (call.method == 'onProgress' && call.arguments is Map) {
            final data = call.arguments as Map;
            final progress = data['progress'];
            if (progress is num) {
              _nativeProgress[data['waveOutFile']]?.call(
                (progress / 100).clamp(0, 1),
              );
            }
          }
        });
  final Future<Directory> Function()? cacheDirectory;
  final WaveformExtractor? extractor;
  final _pending = <String, Future<AudioWaveform>>{};
  Future<void> _tail = Future.value();
  WaveformService({this.cacheDirectory, this.extractor});

  Future<File> _cache(String path) async {
    final stat = await File(path).stat();
    if (stat.type != FileSystemEntityType.file) {
      throw const FileSystemException('Audio file is unavailable');
    }
    final hash = sha256.convert(
      utf8.encode(
        'waveform-v1|$path|${stat.size}|${stat.modified.microsecondsSinceEpoch}',
      ),
    );
    final root = cacheDirectory == null
        ? Directory('${(await getTemporaryDirectory()).path}/waveforms')
        : await cacheDirectory!();
    await root.create(recursive: true);
    return File('${root.path}/$hash.json');
  }

  Future<AudioWaveform?> cached(String path) async {
    final file = await _cache(path);
    if (!await file.exists()) return null;
    try {
      return AudioWaveform.fromJson(
        jsonDecode(await file.readAsString()) as Map<String, dynamic>,
      );
    } on FormatException {
      await file.delete();
      return null;
    } on TypeError {
      await file.delete();
      return null;
    }
  }

  Future<AudioWaveform> generate(
    String path,
    Duration duration, {
    void Function(double)? onProgress,
  }) async {
    final cache = await _cache(path);
    if (_pending.containsKey(cache.path)) return _pending[cache.path]!;
    final existing = await cached(path);
    if (existing != null) return existing;
    // Recheck after asynchronous cache reads: concurrent callers share one decode.
    if (_pending.containsKey(cache.path)) return _pending[cache.path]!;
    final work = _tail.then((_) async {
      final result = await (extractor ?? _extract)(
        path,
        duration,
        onProgress ?? (_) {},
      );
      AudioWaveform.fromJson(result.toJson()); // Validate before persisting.
      // Source identity must still match after decoding.
      if ((await _cache(path)).path != cache.path) {
        throw const FileSystemException(
          'Audio changed during waveform generation',
        );
      }
      final temporary = File('${cache.path}.tmp');
      await temporary.writeAsString(jsonEncode(result.toJson()), flush: true);
      await temporary.rename(cache.path);
      notifyListeners();
      return result;
    });
    _pending[cache.path] = work;
    _tail = work.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    try {
      return await work;
    } finally {
      _pending.remove(cache.path);
    }
  }

  static Future<AudioWaveform> _extract(
    String path,
    Duration duration,
    void Function(double) progress,
  ) async {
    progress(0);
    final wave = await compute(_readPcmPath, path);
    if (wave != null) progress(1);
    if (wave != null) return wave;
    if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
      final temporary = await getTemporaryDirectory();
      await temporary.create(recursive: true);
      final output = File(
        '${temporary.path}/crisper-wave-${DateTime.now().microsecondsSinceEpoch}.wave',
      );
      try {
        _nativeProgress[output.path] = progress;
        // Use the plugin's native decoder with our validated streaming parser.
        // Its 0.0.7 Dart parser mistakes header bytes for element counts/offsets,
        // which breaks short tracks and includes header values in 16-bit peaks.
        await _nativeChannel.invokeMethod<void>('extract', {
          'audioInPath': path,
          'waveOutPath': output.path,
          'pixelsPerSecond': 1,
          'samplesPerPixel': null,
        });
        return await readNativeWaveform(output);
      } finally {
        _nativeProgress.remove(output.path);
        if (await output.exists()) await output.delete();
      }
    }
    return _ffmpeg(path, duration, progress);
  }

  static Future<AudioWaveform> _ffmpeg(
    String path,
    Duration duration,
    void Function(double) progress,
  ) async {
    if (duration <= Duration.zero) {
      throw const FormatException('Load the track duration first');
    }
    Process process;
    try {
      process = await Process.start('ffmpeg', [
        '-v',
        'error',
        '-nostdin',
        '-i',
        path,
        '-vn',
        '-ac',
        '1',
        '-ar',
        '8000',
        '-f',
        's16le',
        'pipe:1',
      ]);
    } on ProcessException {
      throw const FileSystemException(
        'Install FFmpeg to generate compressed-audio waveforms on Windows/Linux. PCM WAV works without it.',
      );
    }
    // Drain diagnostics without retaining an unbounded log or source paths.
    final errors = process.stderr.drain<void>();
    final bins = List.filled(512, 0.0);
    final expected = math.max(1, duration.inMicroseconds * 8000 ~/ 1000000);
    var samples = 0;
    int? low;
    try {
      await for (final chunk in process.stdout) {
        for (final byte in chunk) {
          if (low == null) {
            low = byte;
            continue;
          }
          var sample = low | byte << 8;
          low = null;
          if (sample >= 32768) sample -= 65536;
          final bin = math.min(511, samples * 512 ~/ expected);
          bins[bin] = math.max(bins[bin], sample.abs() / 32768);
          samples++;
        }
        progress((samples / expected).clamp(0, .99));
      }
      final code = await process.exitCode;
      await errors;
      if (code != 0 || samples == 0) {
        throw const FormatException('FFmpeg could not decode this audio');
      }
      progress(1);
      return AudioWaveform(
        bins,
        Duration(microseconds: samples * 1000000 ~/ 8000),
      );
    } finally {
      process.kill();
    }
  }
}

/// Stream PCM WAV directly on every platform; never retain a book's PCM in RAM.
Future<AudioWaveform?> extractPcmWave(
  File file,
  void Function(double) progress,
) async {
  final input = await file.open();
  try {
    final header = await input.read(12);
    if (header.length < 12 ||
        ascii.decode(header.sublist(0, 4), allowInvalid: true) != 'RIFF' ||
        ascii.decode(header.sublist(8), allowInvalid: true) != 'WAVE') {
      return null;
    }
    int? channels, rate, bits, format, offset, length;
    final size = await input.length();
    while (await input.position() + 8 <= size) {
      final chunk = await input.read(8);
      final name = ascii.decode(chunk.sublist(0, 4), allowInvalid: true);
      final count = ByteData.sublistView(chunk).getUint32(4, Endian.little);
      final start = await input.position();
      if (count > size - start) {
        throw const FormatException('Truncated WAV data');
      }
      if (name == 'fmt ' && count >= 16) {
        final data = ByteData.sublistView(await input.read(16));
        format = data.getUint16(0, Endian.little);
        channels = data.getUint16(2, Endian.little);
        rate = data.getUint32(4, Endian.little);
        bits = data.getUint16(14, Endian.little);
      }
      if (name == 'data') {
        offset = start;
        length = count;
      }
      if (offset != null && format != null) break;
      await input.setPosition(start + count + count % 2);
    }
    if (offset == null ||
        length == null ||
        channels == null ||
        channels < 1 ||
        channels > 32 ||
        rate == null ||
        rate < 1 ||
        bits == null ||
        !(format == 1 && [8, 16, 24, 32].contains(bits) ||
            format == 3 && bits == 32)) {
      return null;
    }
    final width = bits ~/ 8, frameWidth = channels * (bits ~/ 8);
    final frames = length ~/ frameWidth;
    if (frames == 0) {
      throw const FormatException('WAV contains no audio samples');
    }
    final peaks = List.filled(math.min(512, frames), 0.0);
    await input.setPosition(offset);
    var frame = 0;
    while (frame < frames) {
      final wanted = math.min(4096, frames - frame);
      final bytes = await input.read(wanted * frameWidth);
      if (bytes.length != wanted * frameWidth) {
        throw const FormatException('Truncated WAV audio');
      }
      final data = ByteData.sublistView(bytes);
      for (var i = 0; i < wanted; i++, frame++) {
        var peak = 0.0;
        for (var channel = 0; channel < channels; channel++) {
          final at = i * frameWidth + channel * width;
          double sample;
          if (format == 3) {
            sample = data.getFloat32(at, Endian.little);
          } else if (bits == 8) {
            sample = (data.getUint8(at) - 128) / 128;
          } else if (bits == 16) {
            sample = data.getInt16(at, Endian.little) / 32768;
          } else if (bits == 24) {
            var value =
                data.getUint8(at) |
                data.getUint8(at + 1) << 8 |
                data.getUint8(at + 2) << 16;
            if (value >= 8388608) value -= 16777216;
            sample = value / 8388608;
          } else {
            sample = data.getInt32(at, Endian.little) / 2147483648;
          }
          if (sample.isFinite) peak = math.max(peak, sample.abs().clamp(0, 1));
        }
        final bin = frame * peaks.length ~/ frames;
        peaks[bin] = math.max(peaks[bin], peak);
      }
      progress(frame / frames);
    }
    return AudioWaveform(
      peaks,
      Duration(microseconds: frames * 1000000 ~/ rate),
    );
  } finally {
    await input.close();
  }
}

Future<AudioWaveform?> _readPcmPath(String path) =>
    extractPcmWave(File(path), (_) {});

/// Parse the 20-byte audiowaveform header and signed min/max PCM pairs.
Future<AudioWaveform> readNativeWaveform(File file) async {
  final source = await file.open();
  try {
    final header = await source.read(20);
    if (header.length != 20) {
      throw const FormatException('Truncated waveform header');
    }
    final data = ByteData.sublistView(header);
    final version = data.getUint32(0, Endian.little),
        flags = data.getUint32(4, Endian.little);
    final rate = data.getUint32(8, Endian.little),
        samples = data.getUint32(12, Endian.little),
        count = data.getUint32(16, Endian.little);
    if (version != 1 || flags > 1 || rate == 0 || samples == 0 || count == 0) {
      throw const FormatException('Unsupported waveform header');
    }
    final stride = flags == 0 ? 4 : 2;
    if (20 + count * stride > await source.length()) {
      throw const FormatException('Truncated waveform samples');
    }
    final peaks = List.filled(math.min(512, count), 0.0);
    var read = 0;
    while (read < count) {
      final size = math.min(4096, count - read);
      final chunk = await source.read(size * stride);
      if (chunk.length != size * stride) {
        throw const FormatException('Truncated waveform samples');
      }
      final values = ByteData.sublistView(chunk);
      for (var index = 0; index < size; index++, read++) {
        final minimum = flags == 0
            ? values.getInt16(index * stride, Endian.little)
            : values.getInt8(index * stride);
        final maximum = flags == 0
            ? values.getInt16(index * stride + 2, Endian.little)
            : values.getInt8(index * stride + 1);
        final amplitude =
            math.max(minimum.abs(), maximum.abs()) / (flags == 0 ? 32768 : 128);
        final bin = read * peaks.length ~/ count;
        peaks[bin] = math.max(peaks[bin], amplitude.clamp(0, 1));
      }
    }
    return AudioWaveform(
      peaks,
      Duration(microseconds: count * samples * 1000000 ~/ rate),
    );
  } finally {
    await source.close();
  }
}
