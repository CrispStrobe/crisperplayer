import 'package:audio_service/audio_service.dart';
import 'package:crisperplayer/services/audio/companion_service.dart';
import 'package:crisperplayer/services/audio/media_library.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/playback_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PlaybackHarness h;
  late MediaLibrary library;
  setUp(() async {
    h = PlaybackHarness();
    await h.init();
    await h.book('Alpha', [60, 60]);
    await h.book('Beta', [120]);
    library = MediaLibrary(h.db, h.playback);
  });
  tearDown(() => h.dispose());
  test(
    'car root, library, queue, chapters and search expose only valid media IDs',
    () async {
      expect(
        (await library.children(AudioService.browsableRootId)).map((e) => e.id),
        ['continue', 'library', 'up-next'],
      );
      expect((await library.children('library')).map((e) => e.id), [
        'book/Alpha',
        'book/Beta',
      ]);
      await h.db.replaceQueue(['Beta', 'Alpha']);
      expect((await library.children('up-next')).map((e) => e.id), [
        'book/Beta',
        'book/Alpha',
      ]);
      expect((await library.children('book/Alpha')).map((e) => e.id), [
        'resume/Alpha',
        'chapters/Alpha',
      ]);
      expect((await library.children('chapters/Alpha')).length, 2);
      expect((await library.search('ALPHA')).single.id, 'book/Alpha');
      expect(await library.children('book/missing'), isEmpty);
      expect(await library.search(''), isEmpty);
    },
  );
  test(
    'car actions use real coordinator for resume and cross-track chapter playback',
    () async {
      await library.play('resume/Alpha');
      expect(h.backend.playing, isTrue);
      await library.play('chapter/Alpha/1');
      expect(h.backend.currentIndex, 1);
      expect(h.backend.playing, isTrue);
      await expectLater(
        library.play('chapter/Alpha/99'),
        throwsFormatException,
      );
      await expectLater(
        library.play('arbitrary-file:///secret'),
        throwsFormatException,
      );
    },
  );
  test(
    'companion controls share pause persistence and configured playback services',
    () async {
      final service = CompanionService(h.db, h.playback);
      await service.command({'action': 'play', 'mediaId': 'book/Alpha'});
      expect(h.backend.playing, isTrue);
      await service.command({'action': 'forward'});
      expect(h.backend.position.inSeconds, 30);
      await service.command({'action': 'pause'});
      expect(h.backend.playing, isFalse);
      expect((await h.db.getBook('Alpha'))!.lastPositionMs, 30000);
      await service.command({'action': 'nextChapter'});
      expect(h.backend.currentIndex, 1);
      await expectLater(
        service.command({'action': 'delete', 'bookId': 'Alpha'}),
        throwsFormatException,
      );
      await service.dispose();
      await expectLater(service.command({'action': 'play'}), throwsStateError);
    },
  );
}
