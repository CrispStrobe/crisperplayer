import 'dart:convert';
import 'dart:io';
import 'package:crisperplayer/cli/control_client.dart';
import 'package:crisperplayer/services/desktop_control_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/playback_harness.dart';
import 'package:crisperplayer/services/db/app_database.dart';

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
    'chapters, track controls, sleep and settings use the shared services',
    () async {
      await h.book('commands', [30, 60]);
      await client.command('load', {'bookId': 'commands'});
      expect(h.backend.playing, isFalse);
      expect(
        await client.command('list', {'query': 'commands', 'sort': 'title'}),
        hasLength(1),
      );
      expect(await client.command('list', {'filter': 'finished'}), isEmpty);
      await client.command('play');
      expect(await client.command('chapters'), hasLength(2));
      await client.command('chapter', {'index': 2});
      expect(h.backend.currentIndex, 1);
      await client.command('skip', {'seconds': 5});
      expect(h.backend.position.inSeconds, 5);
      await client.command('previous');
      expect(h.backend.currentIndex, 0);
      await client.command('next');
      expect(h.backend.currentIndex, 1);
      await client.command('sleep', {'seconds': 60, 'endOfChapter': true});
      expect(h.playback.sleepEndOfChapter, isTrue);
      expect(
        (await client.command('status') as Map)['sleepRemainingMs'],
        60000,
      );
      await client.command('sleep', {'cancel': true});
      expect(h.playback.sleepRemaining, Duration.zero);
      await client.command('settings', {'key': 'themeMode', 'value': 'light'});
      await client.command('settings', {'key': 'seekSeconds', 'value': 60});
      expect(h.settings.themeMode, 'light');
      expect(h.playback.seekSeconds, 60);
      final before = await client.command('settings');
      await expectLater(
        client.command('settings', {'key': 'seekSeconds', 'value': 17}),
        throwsStateError,
      );
      expect(await client.command('settings'), before);
      await client.command('stop');
      expect(h.backend.playing, isFalse);
    },
  );

  test(
    'bookmark editing, seeking, history clearing and metadata restore',
    () async {
      await h.book('metadata', [60]);
      await client.command('play', {'bookId': 'metadata'});
      await client.command('seek', {'seconds': 7});
      final bookmark =
          await client.command('bookmark', {
                'title': 'Original',
                'note': 'Note',
              })
              as Map;
      final id = bookmark['bookmarkId'] as String;
      await client.command('bookmark-edit', {
        'id': id,
        'title': 'Edited',
        'note': 'Updated',
      });
      await client.command('bookmark-edit', {'id': id, 'title': 'Edited'});
      await client.command('seek', {'seconds': 1});
      await client.command('bookmark-go', {'id': id});
      expect(h.backend.position.inSeconds, 7);
      final bookmarks = await client.command('bookmarks') as List;
      expect(
        bookmarks.any(
          (row) => row['title'] == 'Edited' && row['note'] == 'Updated',
        ),
        isTrue,
      );
      await client.command('pause');
      expect(await client.command('history'), isNotEmpty);
      final backup = await client.command('export') as Map;
      await expectLater(client.command('clear-history'), throwsStateError);
      await client.command('clear-history', {'confirm': true});
      expect(await client.command('history'), isEmpty);
      await client.command('clear-bookmarks', {'confirm': true});
      expect(await client.command('bookmarks'), isEmpty);
      await client.command('restore', {'data': backup});
      expect(
        await client.command('history', {'bookId': 'metadata'}),
        isNotEmpty,
      );
      expect(
        await client.command('bookmarks', {'bookId': 'metadata'}),
        isNotEmpty,
      );
      await client.command('bookmark-delete', {'id': id});
      expect(
        (await h.db.bookmarksFor('metadata')).any((row) => row.id == id),
        isFalse,
      );
    },
  );

  test(
    'multi-file CLI import keeps natural order and cleans up failed batches',
    () async {
      final ten = File('${h.root.path}/chapter10.wav');
      final two = File('${h.root.path}/chapter2.wav');
      await ten.writeAsBytes([10]);
      await two.writeAsBytes([2]);
      final imported =
          await client.importFiles([ten, two], title: 'Book', author: 'Reader')
              as Map;
      final book = (await h.library.getBook(imported['bookId'] as String))!;
      expect(book.title, 'Book');
      expect(book.author, 'Reader');
      final paths = AppDatabase.decodePaths(book.filePathsJson);
      expect(await File(paths.first).readAsBytes(), [2]);
      expect(await File(paths.last).readAsBytes(), [10]);
      await expectLater(
        client.importFiles([ten, File('${h.root.path}/missing.wav')]),
        throwsA(isA<FileSystemException>()),
      );
      expect(await h.library.allBooks(), hasLength(1));
      await client.command('delete', {'bookId': book.id});
      expect(await two.exists(), isTrue);
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
