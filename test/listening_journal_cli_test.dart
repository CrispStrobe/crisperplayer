import 'dart:io';

import 'package:crisperplayer/cli/control_client.dart';
import 'package:crisperplayer/services/desktop_control_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playback_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late PlaybackHarness h;
  late DesktopControlService server;
  late ControlClient client;

  setUp(() async {
    h = PlaybackHarness();
    await h.init();
    await h.book('a', [100, 100]);
    await h.playback.loadBook('a');
    final descriptor = File('${h.root.path}/journal-cli.json');
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

  Future<void> record() async {
    await client.command('settings', {
      'key': 'listeningJournalEnabled',
      'value': true,
    });
    await h.playback.play();
    h.clock = h.clock.add(const Duration(seconds: 20));
    h.backend.move(const Duration(seconds: 20));
    await h.playback.nextTrack();
    h.clock = h.clock.add(const Duration(seconds: 10));
    h.backend.move(const Duration(seconds: 10));
    await h.playback.pause();
  }

  test(
    'journal exposes dated intervals, events and stable pagination',
    () async {
      expect(
        (await client.command('settings') as Map)['listeningJournalEnabled'],
        isFalse,
      );
      await record();
      final first =
          await client.command('journal', {
                'bookId': 'a',
                'limit': 2,
                'fromUtcMs': DateTime(2026).millisecondsSinceEpoch,
                'beforeUtcMs': DateTime(2026, 1, 2).millisecondsSinceEpoch,
              })
              as Map;
      expect(first['entries'], hasLength(2));
      expect(first['nextCursor'], isA<String>());
      final next =
          await client.command('journal', {
                'bookId': 'a',
                'limit': 2,
                'fromUtcMs': DateTime(2026).millisecondsSinceEpoch,
                'beforeUtcMs': DateTime(2026, 1, 2).millisecondsSinceEpoch,
                'cursor': first['nextCursor'],
              })
              as Map;
      final ids = [
        ...first['entries'],
        ...next['entries'],
      ].map((entry) => entry['id']).toSet();
      expect(ids, hasLength(4));
      final all = (await client.command('journal') as Map)['entries'] as List;
      expect(all.where((entry) => entry['kind'] == 'played'), hasLength(2));
      final jump = all.singleWhere((entry) => entry['kind'] == 'seek');
      expect(jump['reason'], 'next_track');
      expect(jump['targetFilePath'], '/a/1.mp3');
      expect(jump['startedAtMs'], isA<int>());
      expect(jump['utcOffsetMinutes'], isA<int>());
    },
  );

  test(
    'journal passage queries expose actual plays at a source point or range',
    () async {
      await record();
      final point = <String, Object>{
        'bookId': 'a',
        'filePath': '/a/0.mp3',
        'positionMs': 10000,
      };
      final page = await client.command('journal', {'passage': point}) as Map;
      final played = (page['entries'] as List).single as Map;
      expect(played['kind'], 'played');
      expect((played['startMs'], played['endMs']), (0, 20000));
      expect(played['filePath'], '/a/0.mp3');
      final boundary =
          await client.command('journal', {
                'passage': {...point, 'positionMs': 20000},
              })
              as Map;
      // The next-track event starts at this endpoint, but is not a play.
      expect(boundary['entries'], isEmpty);
      final range =
          await client.command('journal', {
                'passage': {
                  'bookId': 'a',
                  'filePath': '/a/0.mp3',
                  'startMs': 19000,
                  'endMs': 21000,
                },
              })
              as Map;
      expect((range['entries'] as List).single['id'], played['id']);
      final destination =
          await client.command('journal', {
                'passage': {...point, 'filePath': '/a/1.mp3', 'positionMs': 0},
              })
              as Map;
      expect(destination['entries'], hasLength(1));
      expect((destination['entries'] as List).single['kind'], 'played');
      expect(h.backend.currentIndex, 1);
      expect(h.backend.position.inSeconds, 10);
      expect(h.backend.playing, isFalse);
    },
  );

  test(
    'journal-open validates entry endpoints and creates a return bookmark',
    () async {
      await record();
      final all = (await client.command('journal') as Map)['entries'] as List;
      final jump = all.singleWhere((entry) => entry['kind'] == 'seek');
      final opened =
          await client.command('journal-open', {
                'id': jump['id'],
                'point': 'start',
              })
              as Map;
      expect(opened['paused'], isTrue);
      expect(opened['savedBookmarkId'], isA<String>());
      expect(h.backend.currentIndex, 0);
      expect(h.backend.position.inSeconds, 20);
      expect(h.backend.playing, isFalse);
      await client.command('journal-open', {
        'id': jump['id'],
        'point': 'target',
      });
      expect(h.backend.currentIndex, 1);
      expect(h.backend.position, Duration.zero);
      final played = all.firstWhere((entry) => entry['kind'] == 'played');
      await expectLater(
        client.command('journal-open', {'id': played['id'], 'point': 'target'}),
        throwsStateError,
      );
      expect(h.backend.currentIndex, 1);
      expect(h.backend.position, Duration.zero);
    },
  );

  test(
    'journal consent, filters and clearing reject malformed commands',
    () async {
      await record();
      for (final args in <Map<String, Object>>[
        {'bookId': 1},
        {'fromUtcMs': 1.5},
        {'limit': 0},
        {'fromUtcMs': 20, 'beforeUtcMs': 10},
        {'cursor': 'invalid'},
        {'passage': 'not-an-object'},
        {
          'passage': {'bookId': 'a', 'filePath': '/a/0.mp3'},
        },
        {
          'passage': {'bookId': 'a', 'filePath': '/a/0.mp3', 'positionMs': 1.5},
        },
        {
          'passage': {'bookId': 'a', 'filePath': '/a/0.mp3', 'positionMs': -1},
        },
        {
          'passage': {
            'bookId': 'a',
            'filePath': '/a/0.mp3',
            'startMs': 2000,
            'endMs': 1000,
          },
        },
        {
          'passage': {
            'bookId': 'a',
            'filePath': '/a/0.mp3',
            'positionMs': 1000,
            'startMs': 0,
            'endMs': 2000,
          },
        },
        {
          'bookId': 'b',
          'passage': {
            'bookId': 'a',
            'filePath': '/a/0.mp3',
            'positionMs': 1000,
          },
        },
      ]) {
        await expectLater(client.command('journal', args), throwsStateError);
      }
      await expectLater(
        client.command('settings', {
          'key': 'listeningJournalEnabled',
          'value': 'true',
        }),
        throwsStateError,
      );
      await expectLater(client.command('clear-journal'), throwsStateError);
      expect((await client.command('journal') as Map)['entries'], isNotEmpty);
      await client.command('settings', {
        'key': 'listeningJournalEnabled',
        'value': false,
      });
      await client.command('clear-journal', {'confirm': true, 'bookId': 'a'});
      expect((await client.command('journal') as Map)['entries'], isEmpty);
      expect((await client.command('coverage') as Map)['playedMs'], 30000);
    },
  );

  test('desktop processing preference is explicit and validated', () async {
    expect(
      (await client.command('settings') as Map)['desktopSpeedProcessing'],
      'sonic',
    );
    final changed =
        await client.command('settings', {
              'key': 'desktopSpeedProcessing',
              'value': 'wsola',
            })
            as Map;
    expect(changed['desktopSpeedProcessing'], 'wsola');
    await expectLater(
      client.command('settings', {
        'key': 'desktopSpeedProcessing',
        'value': 'pretendProcessor',
      }),
      throwsStateError,
    );
    expect(h.settings.desktopSpeedProcessing, 'wsola');
    expect(h.backend.speed, 1);
  });
}
