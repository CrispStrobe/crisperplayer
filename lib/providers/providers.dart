import '../services/server/remote_library_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../services/db/app_database.dart';
import '../services/library_service.dart';
import '../services/bookmark_service.dart';
import '../services/history_service.dart';
import '../services/settings_service.dart';
import '../services/audio/playback_service.dart';
import '../services/share_intake_service.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

final libraryServiceProvider = Provider<LibraryService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return LibraryService(db);
});

final bookmarkServiceProvider = Provider<BookmarkService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return BookmarkService(db);
});

final historyServiceProvider = Provider<HistoryService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return HistoryService(db);
});

// settings is overridden in main with real prefs
final settingsProvider = ChangeNotifierProvider<SettingsService>(
  (ref) => throw UnimplementedError('settingsProvider not overridden'),
);

final playbackProvider = Provider<PlaybackService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final lib = ref.watch(libraryServiceProvider);
  final bm = ref.watch(bookmarkServiceProvider);
  final hist = ref.watch(historyServiceProvider);
  final svc = PlaybackService(
    db: db,
    library: lib,
    bookmarks: bm,
    history: hist,
    settings: ref.read(settingsProvider),
  );
  ref.onDispose(() => svc.dispose());
  return svc;
});

final shareIntakeProvider = Provider<ShareIntakeService>((ref) {
  final lib = ref.watch(libraryServiceProvider);
  final svc = ShareIntakeService(library: lib);
  ref.onDispose(() => svc.dispose());
  return svc;
});

// UI state
final selectedBookIdProvider = StateProvider<String?>((_) => null);

final libraryBooksProvider = StreamProvider<List<Book>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.watchAllBooks();
});

final bookProvider = StreamProvider.family<Book?, String>((ref, id) {
  final db = ref.watch(appDatabaseProvider);
  return db.watchBook(id);
});

final chaptersProvider = StreamProvider.family<List<Chapter>, String>((
  ref,
  bookId,
) {
  final db = ref.watch(appDatabaseProvider);
  return db.watchChapters(bookId);
});

final bookmarksProvider = StreamProvider.family<List<Bookmark>, String>((
  ref,
  bookId,
) {
  final db = ref.watch(appDatabaseProvider);
  return db.watchBookmarks(bookId);
});

final historyProvider = StreamProvider<List<ListeningHistoryData>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.watchHistory();
});

final remoteLibraryProvider = ChangeNotifierProvider<RemoteLibraryService>((
  ref,
) {
  return RemoteLibraryService(ref.watch(libraryServiceProvider));
});
