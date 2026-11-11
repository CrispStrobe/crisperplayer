library just_audio_media_kit;

import 'package:media_kit/media_kit.dart';

Future<void> setProperty(Player player, String key, dynamic value) {
  // noop
  return Future.value();
}

Future<List<String>> availableAudioFilters(Player player) async => const [];

Future<void> setAudioFilterChecked(Player player, String filter) async {
  throw UnsupportedError('This speed processor requires native libmpv.');
}
