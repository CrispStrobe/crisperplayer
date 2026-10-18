import 'package:flutter/services.dart';

/// Effects are optional. A device/codec failure leaves normal playback running.
class AndroidAudioEffects {
  static const channel = MethodChannel(
    'com.crispstrobe.crisperplayer/audio-effects',
  );
  String? error;
  bool _active = false;
  Future<void> _pending = Future.value();

  Future<void> configure(int? session, double boostDb, String equalizer) {
    return _pending = _pending.then((_) async {
      if ((session == null ||
              session <= 0 ||
              (boostDb == 0 && equalizer == 'off')) &&
          !_active) {
        return;
      }
      try {
        await channel.invokeMethod<void>('configure', {
          'sessionId': session ?? 0,
          'boostDb': boostDb,
          'equalizer': equalizer,
        });
        _active =
            session != null &&
            session > 0 &&
            (boostDb != 0 || equalizer != 'off');
        error = null;
      } on PlatformException {
        error = 'Audio effects are unavailable on this device.';
        _active = false;
      } on MissingPluginException {
        error = 'Audio effects are unavailable on this device.';
        _active = false;
      }
    });
  }

  Future<void> dispose() => configure(0, 0, 'off');
}

abstract interface class AudioEffectsBackend {
  bool get supportsAudioEffects;
  String? get audioEffectsError;
  Future<void> setAudioEffects({
    required double boostDb,
    required String equalizer,
  });
}
