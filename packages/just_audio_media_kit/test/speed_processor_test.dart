import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_media_kit/src/speed_processor.dart';

void main() {
  test('older or unavailable inventories retain existing mpv choices', () {
    expect(MediaKitSpeedProcessor.supportedBy(const []), {
      MediaKitSpeedProcessor.automatic,
      MediaKitSpeedProcessor.legacyScaletempo,
    });
    expect(MediaKitSpeedProcessor.supportedBy(['scaletempo2', 'rubberband']), {
      MediaKitSpeedProcessor.automatic,
      MediaKitSpeedProcessor.legacyScaletempo,
    });
  });

  test('portable choices require the actual compiled mpv filter', () {
    final supported = MediaKitSpeedProcessor.supportedBy(['crisperdsp']);
    expect(
      supported,
      containsAll({
        MediaKitSpeedProcessor.sonic,
        MediaKitSpeedProcessor.wsola,
        MediaKitSpeedProcessor.signalsmith,
        MediaKitSpeedProcessor.bungee,
      }),
    );
    expect(supported, isNot(contains(MediaKitSpeedProcessor.atempo)));
    expect(() => supported.clear(), throwsUnsupportedError);
  });

  test('atempo requires native tempo wrapper and linked FFmpeg filter', () {
    for (final filters in [
      <String>[],
      ['atempo'],
      ['lavfi-tempo'],
    ]) {
      expect(
        MediaKitSpeedProcessor.supportedBy(filters),
        isNot(contains(MediaKitSpeedProcessor.atempo)),
      );
    }
    expect(
      MediaKitSpeedProcessor.supportedBy(['lavfi-tempo', 'atempo']),
      contains(MediaKitSpeedProcessor.atempo),
    );
  });

  test('default paths never inject an optional filter', () {
    expect(MediaKitSpeedProcessor.automatic.audioFilter, isNull);
    expect(MediaKitSpeedProcessor.legacyScaletempo.audioFilter, isNull);
    expect(
      MediaKitSpeedProcessor.atempo.audioFilter,
      'lavfi-tempo=filter=atempo',
    );
  });
}
