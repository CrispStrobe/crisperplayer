import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:crisperplayer/main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crisperplayer/services/db/app_database.dart';
import 'package:crisperplayer/services/settings_service.dart';
import 'package:crisperplayer/services/audio/playback_service.dart';
import 'package:crisperplayer/services/library_service.dart';
import 'package:crisperplayer/services/bookmark_service.dart';
import 'package:crisperplayer/services/history_service.dart';
import 'package:crisperplayer/providers/providers.dart';
import 'package:drift/native.dart';

void main() {
  testWidgets('Library screen loads empty state', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = SettingsService(prefs);
    final db = AppDatabase.forTesting(NativeDatabase.memory());

    final playback = PlaybackService(db: db, library: LibraryService(db), bookmarks: BookmarkService(db), history: HistoryService(db));

    await tester.pumpWidget(ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        settingsProvider.overrideWithValue(settings),
        playbackProvider.overrideWithValue(playback),
      ],
      child: CrisperPlayerApp(settings: settings),
    ));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
    expect(find.text('CrisperPlayer'), findsOneWidget);
    await db.close();
  });
}
