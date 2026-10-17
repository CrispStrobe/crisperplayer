import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final sharedPrefsProvider = FutureProvider<SharedPreferences>((_) => SharedPreferences.getInstance());

final settingsServiceProvider = Provider<SettingsService>((ref) {
  throw UnimplementedError('Override in main.dart with actual SharedPreferences');
});

class SettingsService {
  final SharedPreferences _p;
  SettingsService(this._p);

  double get playbackSpeed => _p.getDouble('playback_speed') ?? 1.0;
  set playbackSpeed(double v) => _p.setDouble('playback_speed', v);

  double get volume => _p.getDouble('volume') ?? 1.0;
  set volume(double v) => _p.setDouble('volume', v);

  Duration get autoBookmarkInterval => Duration(seconds: _p.getInt('auto_bookmark_sec') ?? 300);
  set autoBookmarkInterval(Duration d) => _p.setInt('auto_bookmark_sec', d.inSeconds);

  bool get autoBookmarkEnabled => _p.getBool('auto_bookmark_enabled') ?? true;
  set autoBookmarkEnabled(bool v) => _p.setBool('auto_bookmark_enabled', v);

  Duration get sleepTimerDefault => Duration(minutes: _p.getInt('sleep_default_min') ?? 0);
  set sleepTimerDefault(Duration d) => _p.setInt('sleep_default_min', d.inMinutes);

  bool get skipSilence => _p.getBool('skip_silence') ?? false;
  set skipSilence(bool v) => _p.setBool('skip_silence', v);

  int get seekSeconds => _p.getInt('seek_sec') ?? 30;
  set seekSeconds(int v) => _p.setInt('seek_sec', v);

  String get themeMode => _p.getString('theme_mode') ?? 'system';
  set themeMode(String v) => _p.setString('theme_mode', v);

  bool get resumeOnLaunch => _p.getBool('resume_on_launch') ?? true;
  set resumeOnLaunch(bool v) => _p.setBool('resume_on_launch', v);
}
