import 'screens/browser_upload_screen.dart';
import 'services/sync/folder_progress_service.dart';
import 'services/audio/companion_service.dart';
import 'services/audio/media_library.dart';
import 'services/sync/plex_progress_service.dart';
import 'dart:async';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'providers/providers.dart';
import 'screens/library_screen.dart';
import 'screens/player_screen.dart';
import 'screens/bookmarks_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/sync_settings_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/settings_service.dart';
import 'services/server/remote_library_service.dart';
import 'services/db/app_database.dart';
import 'services/audio/audio_handler.dart';
import 'services/audio/playback_service.dart';
import 'services/library_service.dart';
import 'services/bookmark_service.dart';
import 'services/history_service.dart';
import 'services/share_intake_service.dart';
import 'services/desktop_control_service.dart';
import 'theme/app_theme.dart';
import 'services/native_licenses.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerNativeLicenses();
  if (kIsWeb) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'CrisperPlayer requires the installed Android, iOS or desktop app. '
                'Browser playback and library storage are not available in this version.',
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }
  AppDatabase? db;
  PlaybackService? playback;
  AudioPlayer? player;
  DesktopControlService? control;
  try {
    if (Platform.isWindows || Platform.isLinux) {
      JustAudioMediaKit.ensureInitialized();
    }
    final prefs = await SharedPreferences.getInstance();
    // Earlier versions stored simulated sign-ins. They are not real accounts.
    for (final key
        in prefs.getKeys().where((key) => key.startsWith('sync_')).toList()) {
      await prefs.remove(key);
    }
    final settings = SettingsService(prefs);
    final database = db = AppDatabase();
    player = AudioPlayer(handleInterruptions: false);
    final library = LibraryService(database);
    final remote = RemoteLibraryService(library);
    final service = playback = PlaybackService(
      db: database,
      library: library,
      bookmarks: BookmarkService(database),
      history: HistoryService(database),
      settings: settings,
      audioPlayer: player,
    );
    if (Platform.isAndroid || Platform.isIOS) {
      final handler = await AudioService.init<CrisperAudioHandler>(
        builder: () => CrisperAudioHandler(player!),
        config: const AudioServiceConfig(
          androidNotificationChannelId:
              'com.crispstrobe.crisperplayer.channel.audio',
          androidNotificationChannelName: 'CrisperPlayer',
          androidNotificationChannelDescription: 'Audiobook playback controls',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
          androidNotificationIcon: 'mipmap/ic_launcher',
          artDownscaleWidth: 800,
          artDownscaleHeight: 800,
        ),
      );
      handler.library = MediaLibrary(database, service);
      service.attachAudioHandler(handler);
    }
    await service.init();
    final progressSync = PlexProgressService(
      library,
      remote,
      isBookOpen: (id) => service.currentBookId == id,
    );
    progressSync.start();
    final folderSync = FolderProgressService(
      library,
      remote,
      isBookOpen: (id) => service.currentBookId == id,
    );
    folderSync.start();
    if ((Platform.isMacOS || Platform.isLinux || Platform.isWindows) &&
        (kDebugMode || const bool.fromEnvironment('CRISPERPLAYER_CLI'))) {
      try {
        final directory = await getApplicationSupportDirectory();
        control = DesktopControlService(
          library: library,
          playback: service,
          descriptor: File('${directory.path}/cli.json'),
          remote: remote,
          progressSync: progressSync,
          folderSync: folderSync,
        );
        await control.start();
      } catch (error) {
        debugPrint('Desktop CLI could not start: $error');
      }
    }
    String? restoreError;
    try {
      await service.restoreLastBook();
    } catch (e) {
      restoreError = 'Could not restore your last book: $e';
    }
    final companion = CompanionService(database, service);
    await companion.init();
    final shareIntake = ShareIntakeService(library: library);
    runApp(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWith((ref) {
            ref.onDispose(
              () => unawaited(() async {
                await shareIntake.dispose();
                await control?.dispose();
                await companion.dispose();
                await folderSync.shutdown();
                await progressSync.shutdown();
                await service.dispose();
                await database.close();
              }()),
            );
            return database;
          }),
          settingsProvider.overrideWith((ref) => settings),
          playbackProvider.overrideWithValue(service),
          libraryServiceProvider.overrideWithValue(library),
          remoteLibraryProvider.overrideWith((ref) => remote),
          plexProgressProvider.overrideWith((ref) => progressSync),
          folderProgressProvider.overrideWith((ref) => folderSync),
          shareIntakeProvider.overrideWithValue(shareIntake),
        ],
        child: CrisperPlayerApp(
          settings: settings,
          prefs: prefs,
          startupMessage: restoreError,
        ),
      ),
    );
    // A release-APK smoke test waits for this after all native services start.
    debugPrint('CrisperPlayer startup complete');
  } catch (e, stack) {
    debugPrint('Startup failed: $e\n$stack');
    await control?.dispose();
    if (playback != null) {
      await playback.dispose();
    } else {
      await player?.dispose();
    }
    await db?.close();
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'CrisperPlayer could not start. Please restart the app.\n\n$e',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CrisperPlayerApp extends ConsumerStatefulWidget {
  final SettingsService settings;
  final SharedPreferences prefs;
  final String? startupMessage;
  const CrisperPlayerApp({
    super.key,
    required this.settings,
    required this.prefs,
    this.startupMessage,
  });
  @override
  ConsumerState<CrisperPlayerApp> createState() => _CrisperPlayerAppState();
}

class _CrisperPlayerAppState extends ConsumerState<CrisperPlayerApp>
    with WidgetsBindingObserver {
  late final GoRouter _router;
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _router = GoRouter(
      refreshListenable: widget.settings,
      initialLocation: widget.settings.onboardingDone ? '/' : '/onboarding',
      redirect: (context, state) {
        final done = widget.settings.onboardingDone;
        final onboarding = state.matchedLocation == '/onboarding';
        if (!done && !onboarding) return '/onboarding';
        if (done && onboarding) return '/';
        return null;
      },
      routes: [
        GoRoute(path: '/', builder: (_, _) => const LibraryScreen()),
        GoRoute(
          path: '/onboarding',
          builder: (_, _) => const OnboardingScreen(),
        ),
        GoRoute(
          path: '/player/:bookId',
          builder: (_, s) => PlayerScreen(bookId: s.pathParameters['bookId']!),
        ),
        GoRoute(
          path: '/bookmarks/:bookId',
          builder: (_, s) =>
              BookmarksScreen(bookId: s.pathParameters['bookId']!),
        ),
        GoRoute(path: '/history', builder: (_, _) => const HistoryScreen()),
        GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
        GoRoute(
          path: '/settings/upload',
          builder: (_, _) => const BrowserUploadScreen(),
        ),
        GoRoute(
          path: '/settings/sync',
          builder: (_, _) => const SyncSettingsScreen(),
        ),
      ],
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.startupMessage != null) _message(widget.startupMessage!);
      unawaited(
        ref
            .read(shareIntakeProvider)
            .init(
              onImported: (id, paths) async {
                if (!mounted || id == null) return;
                _message('Imported ${paths.length} file(s)');
                if (widget.settings.onboardingDone) _router.go('/player/$id');
              },
              onError: _message,
              onInfo: _message,
            ),
      );
    });
  }

  void _message(String message) {
    if (mounted) {
      _messenger.currentState?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(shareIntakeProvider).handleInitialMedia());
    }
  }

  @override
  Widget build(BuildContext context) {
    // Establish the resource owner's lifetime even while onboarding is visible.
    ref.watch(appDatabaseProvider);
    final settings = ref.watch(settingsProvider);
    final themeMode = switch (settings.themeMode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    return MaterialApp.router(
      title: 'CrisperPlayer',
      scaffoldMessengerKey: _messenger,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}
