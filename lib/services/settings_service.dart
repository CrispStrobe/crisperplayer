import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsService extends ChangeNotifier {
  final SharedPreferences _p;
  SettingsService(this._p);

  void _changed(Future<bool> write) {
    notifyListeners();
  }

  double get playbackSpeed =>
      (_p.getDouble('playback_speed') ?? 1.0).clamp(0.5, 3.0);
  set playbackSpeed(double v) =>
      _changed(_p.setDouble('playback_speed', v.clamp(0.5, 3.0)));
  double get volume => (_p.getDouble('volume') ?? 1.0).clamp(0.0, 1.0);
  set volume(double v) => _changed(_p.setDouble('volume', v.clamp(0.0, 1.0)));
  Duration get autoBookmarkInterval => Duration(
    seconds: (_p.getInt('auto_bookmark_sec') ?? 300).clamp(1, 86400),
  );
  set autoBookmarkInterval(Duration d) =>
      _changed(_p.setInt('auto_bookmark_sec', d.inSeconds.clamp(1, 86400)));
  bool get autoBookmarkEnabled => _p.getBool('auto_bookmark_enabled') ?? true;
  set autoBookmarkEnabled(bool v) =>
      _changed(_p.setBool('auto_bookmark_enabled', v));
  Duration get sleepTimerDefault =>
      Duration(minutes: _p.getInt('sleep_default_min') ?? 0);
  set sleepTimerDefault(Duration d) =>
      _changed(_p.setInt('sleep_default_min', d.inMinutes));
  bool get skipSilence => _p.getBool('skip_silence') ?? false;
  set skipSilence(bool v) => _changed(_p.setBool('skip_silence', v));
  int get seekSeconds {
    final v = _p.getInt('seek_sec') ?? 30;
    return [10, 15, 30, 60].contains(v) ? v : 30;
  }

  set seekSeconds(int v) => _changed(_p.setInt('seek_sec', v));
  String get themeMode {
    final v = _p.getString('theme_mode') ?? 'system';
    return ['system', 'light', 'dark'].contains(v) ? v : 'system';
  }

  set themeMode(String v) => _changed(_p.setString('theme_mode', v));
  int get smartRewindSeconds =>
      (_p.getInt('smart_rewind_sec') ?? 5).clamp(0, 60);
  set smartRewindSeconds(int v) =>
      _changed(_p.setInt('smart_rewind_sec', v.clamp(0, 60)));
  int get smartRewindAfterSeconds =>
      (_p.getInt('smart_rewind_after_sec') ?? 60).clamp(0, 86400);
  set smartRewindAfterSeconds(int v) =>
      _changed(_p.setInt('smart_rewind_after_sec', v.clamp(0, 86400)));
  double get boostDb => (_p.getDouble('boost_db') ?? 0).clamp(0, 12);
  set boostDb(double value) =>
      _changed(_p.setDouble('boost_db', value.clamp(0, 12)));
  String get equalizer {
    final value = _p.getString('equalizer') ?? 'off';
    return ['off', 'speech', 'warm', 'bass-reduction'].contains(value)
        ? value
        : 'off';
  }

  set equalizer(String value) => _changed(_p.setString('equalizer', value));
  bool get resumeOnLaunch => _p.getBool('resume_on_launch') ?? true;
  set resumeOnLaunch(bool v) => _changed(_p.setBool('resume_on_launch', v));
  bool get onboardingDone =>
      _p.getBool('onboarding_done') ??
      _p.getBool('onboarding_completed') ??
      false;
  set onboardingDone(bool v) {
    _p.setBool('onboarding_completed', v);
    _changed(_p.setBool('onboarding_done', v));
  }
}
