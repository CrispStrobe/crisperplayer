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
import 'services/share_intake_service.dart';
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

  final library = LibraryService(db);
  final playback = PlaybackService(
    db: db,
    library: library,
    bookmarks: BookmarkService(db),
    history: HistoryService(db),
    audioPlayer: sharedPlayer,
  );
  if (audioHandler != null) {
    playback.attachAudioHandler(audioHandler);
  }
  unawaited(playback.init());

  // Inbound share: wire receive_sharing_intent -> LibraryService.importFiles
  // Lifecycle-aware: handles getInitialMedia() (cold start) and getMediaStream() (warm share)
  final shareIntake = ShareIntakeService(library: library);
  // Init without UI callbacks; AppState will re-bind with ScaffoldMessenger/GoRouter when mounted
  unawaited(shareIntake.init());

  runApp(ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      settingsProvider.overrideWithValue(settings),
      playbackProvider.overrideWithValue(playback),
      libraryServiceProvider.overrideWithValue(library),
      shareIntakeProvider.overrideWithValue(shareIntake),
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
  ShareIntakeService? _shareIntake;

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

    // Bind share callbacks once widget is mounted (needs context for SnackBar/navigation)
    WidgetsBinding.instance.addPostFrameCallback((_) => _bindShareIntake());
  }

  void _bindShareIntake() {
    if (!mounted) return;
    try {
      final svc = ref.read(shareIntakeProvider);
      _shareIntake = svc;
      // Re-init with UI callbacks (idempotent inside service)
      unawaited(svc.init(
        onImported: (bookId, paths) async {
          if (!mounted) return;
          final messenger = ScaffoldMessenger.maybeOf(context);
          if (bookId != null) {
            messenger?.showSnackBar(
              SnackBar(content: Text('Imported ${paths.length} file(s)'), action: SnackBarAction(label: 'Open', onPressed: () => _router.go('/player/$bookId'))),
            );
            // Optionally navigate directly to player
            // Defer to avoid calling during build
            Future.microtask(() {
              if (mounted) _router.go('/player/$bookId');
            });
          } else {
            messenger?.showSnackBar(const SnackBar(content: Text('Import failed')));
          }
        },
        onError: (msg) {
          if (!mounted) return;
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(msg)));
        },
        onInfo: (msg) {
          if (!mounted) return;
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 1)));
        },
      ));
      // Also handle any pending initial media now that UI is ready
      unawaited(svc.handleInitialMedia());
    } catch (e) {
      debugPrint('ShareIntake bind failed: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Don't dispose shareIntake here; it lives for app lifetime via ProviderScope override.
    // It will be closed when ProviderScope disposes.
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
    if (state == AppLifecycleState.resumed) {
      // Inbound share: check for pending shares when returning from share sheet
      try {
        final svc = ref.read(shareIntakeProvider);
        unawaited(svc.handleInitialMedia());
      } catch (_) {}
      // Also re-bind in case service was not yet bound
      if (_shareIntake == null) _bindShareIntake();
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
