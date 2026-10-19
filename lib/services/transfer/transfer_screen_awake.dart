import 'dart:io';
import 'package:flutter/services.dart';

/// Only the transfer screen owns this request; it is released on stop/dispose.
class TransferScreenAwake {
  static const channel = MethodChannel(
    'com.crispstrobe.crisperplayer/transfer',
  );
  static Future<void> setEnabled(bool enabled) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      await channel.invokeMethod<void>('keepAwake', enabled);
    } on MissingPluginException {
      // Older native hosts and widget tests have no keep-awake bridge.
    }
  }
}
