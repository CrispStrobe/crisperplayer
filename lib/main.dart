import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audio_session/audio_session.dart';

import 'providers/providers.dart';
import 'screens/library_screen.dart';
import 'screens/player_screen.dart';
import 'screens/bookmarks_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';
import 'services/settings_service.dart';
import 'services/db/app_database.dart';
import 'services/audio/playback_service.dart';
import 'services/library_service.dart';
import 'services/bookmark_service.dart';
import 'services/history_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Audio session — same pattern as CrisperWeaver proves reliable
  try {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.speech());
  } catch (_) {}

  final prefs = await SharedPreferences.getInstance();
  final settings = SettingsService(prefs);
  final db = AppDatabase();

  final playback = PlaybackService(
    db: db,
    library: LibraryService(db),
    bookmarks: BookmarkService(db),
    history: HistoryService(db),
  );
  unawaited(playback.init());

  runApp(ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      settingsProvider.overrideWithValue(settings),
      playbackProvider.overrideWithValue(playback),
    ],
    child: CrisperPlayerApp(settings: settings),
  ));
}

class CrisperPlayerApp extends ConsumerWidget {
  final SettingsService settings;
  const CrisperPlayerApp({super.key, required this.settings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = switch (settings.themeMode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => const LibraryScreen()),
        GoRoute(path: '/player/:bookId', builder: (_, s) => PlayerScreen(bookId: s.pathParameters['bookId']!)),
        GoRoute(path: '/bookmarks/:bookId', builder: (_, s) => BookmarksScreen(bookId: s.pathParameters['bookId']!)),
        GoRoute(path: '/history', builder: (_, __) => const HistoryScreen()),
        GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      ],
    );

    return MaterialApp.router(
      title: 'CrisperPlayer',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

void unawaited(Future<void> f) {}
