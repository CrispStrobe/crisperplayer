import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'providers/providers.dart';
import 'screens/library_screen.dart';
import 'screens/player_screen.dart';
import 'screens/bookmarks_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/settings_service.dart';
import 'services/db/app_database.dart';
import 'services/audio/audio_handler.dart';
import 'services/audio/playback_service.dart';
import 'services/library_service.dart';
import 'services/bookmark_service.dart';
import 'services/history_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // iOS: configure audio session early for background / Control Center.
  // PlaybackService also configures with the same speech preset + Bluetooth/AirPlay,
  // but early config ensures AVAudioSession is ready before any UI.
  try {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
  } catch (_) {}

  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsService(prefs);
  final db = AppDatabase();

  // Shared player for both PlaybackService and audio_service handler.
  // iOS lockscreen artwork + background controls flow through this single player.
  final sharedPlayer = AudioPlayer();
  CrisperAudioHandler? audioHandler;

  // audio_service: lockscreen / Control Center / headset buttons + background task.
  // Only init on mobile (iOS/Android); desktop/web/test fall back to raw AudioPlayer.
  if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) {
    try {
      audioHandler = await AudioService.init<CrisperAudioHandler>(
        builder: () => CrisperAudioHandler(sharedPlayer),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.crispstrobe.crisperplayer.channel.audio',
          androidNotificationChannelName: 'CrisperPlayer',
          androidNotificationChannelDescription: 'Audiobook playback controls',
          androidNotificationOngoing: true,
          androidShowNotificationBadge: true,
          androidStopForegroundOnPause: true,
          androidNotificationIcon: 'mipmap/ic_launcher',
          // iOS: MediaItem artUri + title/artist/album shown via MPNowPlayingInfoCenter.
          // No extra iOS config needed; UIBackgroundModes audio in Info.plist handles background.
          artDownscaleWidth: 800,
          artDownscaleHeight: 800,
        ),
      );
    } catch (e) {
      debugPrint('AudioService init failed (expected on non-mobile / test): $e');
      audioHandler = null;
    }
  }

  final playback = PlaybackService(
    db: db,
    library: LibraryService(db),
    bookmarks: BookmarkService(db),
    history: HistoryService(db),
    audioPlayer: sharedPlayer,
  );
  if (audioHandler != null) {
    playback.attachAudioHandler(audioHandler);
  }
  unawaited(playback.init());

  runApp(ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      settingsProvider.overrideWithValue(settings),
      playbackProvider.overrideWithValue(playback),
    ],
    child: CrisperPlayerApp(settings: settings, prefs: prefs),
  ));
}

class CrisperPlayerApp extends ConsumerStatefulWidget {
  final SettingsService settings;
  final SharedPreferences prefs;
  const CrisperPlayerApp({super.key, required this.settings, required this.prefs});

  @override
  ConsumerState<CrisperPlayerApp> createState() => _CrisperPlayerAppState();
}

class _CrisperPlayerAppState extends ConsumerState<CrisperPlayerApp> with WidgetsBindingObserver {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _router = GoRouter(
      initialLocation: widget.prefs.getBool('onboarding_done') == true ? '/' : '/onboarding',
      redirect: (context, state) {
        final done = widget.prefs.getBool('onboarding_done') == true;
        final isOnboarding = state.matchedLocation == '/onboarding';
        if (!done && !isOnboarding) return '/onboarding';
        if (done && isOnboarding) return '/';
        return null;
      },
      routes: [
        GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
        GoRoute(path: '/', builder: (_, __) => const LibraryScreen()),
        GoRoute(path: '/player/:bookId', builder: (_, s) => PlayerScreen(bookId: s.pathParameters['bookId']!)),
        GoRoute(path: '/bookmarks/:bookId', builder: (_, s) => BookmarksScreen(bookId: s.pathParameters['bookId']!)),
        GoRoute(path: '/history', builder: (_, __) => const HistoryScreen()),
        GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      ],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // persist + auto-bookmark + endSession — but do NOT pause audio
      // so iOS background playback continues when user locks screen.
      final playback = ref.read(playbackProvider);
      playback.handleAppPaused();
    }
    super.didChangeAppLifecycleState(state);
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = switch (widget.settings.themeMode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

    return MaterialApp.router(
      title: 'CrisperPlayer',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}

void unawaited(Future<void> f) {}
