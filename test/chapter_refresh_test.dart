import 'dart:io';
import 'package:crisperplayer/services/db/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/playback_harness.dart';
import 'support/quicktime_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'refresh upgrades an existing book without changing position or bookmarks',
    () async {
      final h = PlaybackHarness();
      await h.init();
      addTearDown(h.dispose);
      final initial = fixture(reference: false);
      final source = await File(
        '${h.root.path}/book.m4b',
      ).writeAsBytes([...atom('mdat', initial.data), ...initial.moov]);
      final id = (await h.library.importFiles([source.path]))!;
      await h.library.updateTrackDuration(id, 0, const Duration(seconds: 20));
      await h.playback.loadBook(id);
      await h.playback.seekBook(const Duration(seconds: 6));
      await h.playback.addManualBookmark(title: 'Keep my place');
      final before = await h.db.bookmarksFor(id);
      final oldChapters = await h.db.chaptersFor(id);
      expect(oldChapters, hasLength(1));
      expect(await h.playback.refreshChapters(id), isFalse);
      expect((await h.db.chaptersFor(id)).single.id, oldChapters.single.id);
      final updated = fixture();
      final book = (await h.db.getBook(id))!;
      final path = AppDatabase.decodePaths(book.filePathsJson).single;
      await File(
        path,
      ).writeAsBytes([...atom('mdat', updated.data), ...updated.moov]);
      expect(await h.playback.refreshChapters(id), isTrue);
      expect(await h.db.chaptersFor(id), hasLength(3));
      expect((await h.db.getBook(id))!.lastPositionMs, 6000);
      expect(
        (await h.db.bookmarksFor(id)).map((b) => b.toJson()),
        before.map((b) => b.toJson()),
      );
      await h.playback.nextChapter();
      expect(h.backend.position.inSeconds, 10);
    },
  );
}
