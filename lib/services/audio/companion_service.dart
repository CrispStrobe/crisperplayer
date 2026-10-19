import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import '../db/app_database.dart';
import 'media_library.dart';
import 'playback_service.dart';

/// A narrow native bridge. No credentials, audio paths or database handle are
/// exposed to a widget or watch. Every action uses the normal playback service.
class CompanionService {
  static const channel = MethodChannel(
    'com.crispstrobe.crisperplayer/companion',
  );
  final MediaLibrary library;
  final PlaybackService playback;
  StreamSubscription<dynamic>? _events;
  Timer? _debounce;
  Map<String, Object?> _snapshot = {};
  bool _disposed = false;
  CompanionService(AppDatabase db, this.playback)
    : library = MediaLibrary(db, playback);
  Future<void> init() async {
    if (!Platform.isIOS && !Platform.isAndroid) return;
    channel.setMethodCallHandler((call) async {
      final args = call.arguments is Map ? (call.arguments as Map) : const {};
      if (call.method == 'browse') {
        return (await library.children(
          args['parent'] as String? ?? 'root',
        )).map(MediaLibrary.encode).toList();
      }
      if (call.method == 'command') return command(args);
      throw MissingPluginException();
    });
    _events = playback.stateStream.listen((_) {
      _debounce ??= Timer(const Duration(seconds: 2), () {
        _debounce = null;
        publish().ignore();
      });
    });
    try {
      final pending = await channel.invokeMethod<Map>('ready');
      if (pending != null) await command(pending);
      await publish();
    } on MissingPluginException {
      /* Unsupported test host. */
    }
  }

  Future<Map<String, Object?>> command(Map args) async {
    if (_disposed) throw StateError('Player is shutting down');
    switch (args['action']) {
      case 'play':
        if (args['mediaId'] is String) {
          await library.play(args['mediaId'] as String);
        } else {
          await playback.play();
        }
      case 'toggle':
        if (playback.state.isPlaying) {
          await playback.pause();
        } else {
          await playback.play();
        }
      case 'pause':
        await playback.pause();
      case 'forward':
        await playback.skipForward(30);
      case 'backward':
        await playback.skipBack(30);
      case 'nextChapter':
        await playback.nextChapter();
      case 'previousChapter':
        await playback.previousChapter();
      default:
        throw const FormatException('Unsupported companion action');
    }
    await publish();
    return _snapshot;
  }

  Future<void> publish() async {
    if (_disposed) return;
    final book = playback.currentBookId == null
        ? null
        : await library.db.getBook(playback.currentBookId!);
    _snapshot = {
      'title': book?.title ?? 'CrisperPlayer',
      'author': book?.author ?? '',
      'playing': playback.state.isPlaying,
      'position': playback.state.position.inSeconds,
      'duration': playback.state.duration.inSeconds,
      'speed': playback.state.speed,
    };
    if (Platform.isIOS || Platform.isAndroid) {
      try {
        await channel.invokeMethod<void>('update', _snapshot);
      } on MissingPluginException {
        /* Unsupported test host. */
      }
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    _debounce?.cancel();
    await _events?.cancel();
    if (Platform.isIOS || Platform.isAndroid) {
      channel.setMethodCallHandler(null);
    }
  }
}
