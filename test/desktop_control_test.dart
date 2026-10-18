import 'dart:convert';
import 'dart:io';
import 'package:crisperplayer/cli/control_client.dart';
import 'package:crisperplayer/services/desktop_control_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/playback_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Exercise real loopback HTTP rather than Flutter's network stub.
  HttpOverrides.global = null;
  late PlaybackHarness h;
  late DesktopControlService server;
  late File descriptor;
  late ControlClient client;
  setUp(() async {
    h = PlaybackHarness();
    await h.init();
    descriptor = File('${h.root.path}/cli.json');
    server = DesktopControlService(
      library: h.library,
      playback: h.playback,
      descriptor: descriptor,
    );
    await server.start();
    client = ControlClient(descriptor);
  });
  tearDown(() async {
    await server.dispose();
    await h.dispose();
  });

  test(
    'CLI controls the production coordinator and persists bookmark/progress',
    () async {
      await h.book('cli-book', [30, 60]);
      expect((await client.command('list') as List).single['id'], 'cli-book');
      await client.command('play', {'bookId': 'cli-book'});
      expect(h.backend.playing, isTrue);
      await client.command('seek', {'seconds': 35});
      expect(h.backend.currentIndex, 1);
      expect(h.backend.position, const Duration(seconds: 5));
      await client.command('speed', {'value': 1.5});
      expect(h.backend.speed, 1.5);
      await client.command('bookmark', {'title': 'From CLI'});
      final bookmarks = await client.command('bookmarks') as List;
      expect(
        bookmarks.any(
          (b) => b['title'] == 'From CLI' && b['positionMs'] == 35000,
        ),
        isTrue,
      );
      await client.command('pause');
      expect(h.backend.playing, isFalse);
      final saved = (await h.db.getBook('cli-book'))!;
      expect(saved.lastPositionMs, 5000);
      expect(saved.lastPositionFilePath, '/cli-book/1.mp3');
      expect(saved.totalProgress, closeTo(35 / 90, 0.001));
      await client.command('delete', {'bookId': 'cli-book'});
      expect(await h.library.getBook('cli-book'), isNull);
      expect(await h.db.bookmarksFor('cli-book'), isEmpty);
      expect(h.playback.currentBookId, isNull);
      final empty = await client.command('status') as Map;
      expect(empty['positionMs'], 0);
      expect(empty['speed'], 1.5);
    },
  );

  test(
    'streamed import is a managed copy and rejects non-audio filenames',
    () async {
      final source = File('${h.root.path}/book.wav');
      await source.writeAsBytes(List.filled(100, 0));
      final imported = await client.importFile(source) as Map;
      await source.delete();
      final book = await h.library.getBook(imported['bookId'] as String);
      expect(book, isNotNull);
      expect(await client.command('list'), hasLength(1));
      final bad = File('${h.root.path}/not-audio.txt');
      await bad.writeAsString('test');
      await expectLater(client.importFile(bad), throwsStateError);
      expect(await h.library.allBooks(), hasLength(1));
    },
  );

  test(
    'rejects unauthenticated and browser requests without mutating playback',
    () async {
      final config = jsonDecode(await descriptor.readAsString()) as Map;
      final http = HttpClient();
      try {
        for (final origin in [false, true]) {
          final req = await http.postUrl(
            Uri.parse('http://127.0.0.1:${config['port']}/command'),
          );
          if (origin) {
            req.headers.set('Authorization', 'Bearer ${config['token']}');
            req.headers.set('Origin', 'https://example.com');
          }
          req.write(jsonEncode({'command': 'speed', 'value': 2}));
          final response = await req.close();
          expect(response.statusCode, HttpStatus.forbidden);
          await response.drain<void>();
        }
        expect(h.backend.speed, 1);
      } finally {
        http.close(force: true);
      }
    },
  );

  test(
    'invalid commands and ranges do not break subsequent requests',
    () async {
      for (final args in [
        {'command': 'speed', 'value': 0},
        {'command': 'seek', 'seconds': -1},
        {'command': 'missing'},
      ]) {
        await expectLater(
          client.command(args['command'] as String, args),
          throwsStateError,
        );
      }
      expect((await client.command('status') as Map)['status'], 'idle');
    },
  );

  test(
    'shutdown removes its descriptor and client gives a useful offline error',
    () async {
      await server.dispose();
      expect(await descriptor.exists(), isFalse);
      await expectLater(client.command('status'), throwsStateError);
    },
  );
}
