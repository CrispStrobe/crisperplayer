import 'package:media_kit/media_kit.dart';

Future<void> setProperty(Player player, String key, dynamic value) async {
  if (player.platform is! NativePlayer) return;
  await (player.platform as NativePlayer).setProperty(key, value);
}

Future<List<String>> availableAudioFilters(Player player) async {
  final native = player.platform;
  if (native is! NativePlayer) return const [];
  final inventory = await native.getProperty('option-info/af/choices');
  return inventory.split(',').map((name) => name.trim()).toList();
}

Future<void> setAudioFilterChecked(Player player, String filter) async {
  final native = player.platform;
  if (native is! NativePlayer) {
    throw UnsupportedError('This speed processor requires native libmpv.');
  }
  // media_kit's public setProperty ignores mpv's integer error result. Read
  // back the filter instead of claiming a failed selection was installed.
  await native.setProperty('af', '@crisper_speed:$filter');
  final installed = await native.getProperty('af');
  final parts = filter.split('=');
  if (!installed.contains('crisper_speed') ||
      !parts.every(installed.contains)) {
    throw StateError('libmpv could not install the selected speed processor.');
  }
}
