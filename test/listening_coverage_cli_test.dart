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
    await h.init(preferences: {'autoBookmarkEnabled': false});
    await h.book('map', [100, 100]);
    await h.playback.loadBook('map');
    final descriptor = File('${h.root.path}/coverage-cli.json');
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

  Future<void> listen(int seconds) async {
    h.clock = h.clock.add(Duration(seconds: seconds));
    h.backend.move(h.backend.position + Duration(seconds: seconds));
  }

  test(
    'coverage JSON exposes unique played ranges and gaps, independent of playhead',
    () async {
      await h.playback.play();
      await h.flush();
      await listen(20);
      await h.playback.seekTrack(0, const Duration(seconds: 60));
      await listen(20);
      final map = await client.command('coverage') as Map;
      expect(map['bookId'], 'map');
      expect(map['playedMs'], 40000);
      expect(map['durationMs'], 200000);
      expect(map['fraction'], .2);
      final first = (map['tracks'] as List).first as Map;
      expect(
        (first['played'] as List).map((row) => [row['startMs'], row['endMs']]),
        [
          [0, 20000],
          [60000, 80000],
        ],
      );
      expect(
        (first['gaps'] as List).map((row) => [row['startMs'], row['endMs']]),
        [
          [20000, 60000],
          [80000, 100000],
        ],
      );
      expect(h.backend.position, const Duration(seconds: 80));
      expect(h.backend.playing, isTrue);
      await h.playback.seekTrack(0, const Duration(seconds: 10));
      await listen(10);
      expect((await client.command('coverage') as Map)['playedMs'], 40000);
    },
  );

  test(
    'coverage jump opens the chosen track paused without marking skipped audio',
    () async {
      await h.playback.play();
      await h.flush();
      await listen(10);
      await client.command('coverage-seek', {
        'bookId': 'map',
        'filePath': '/map/1.mp3',
        'positionMs': 60000,
      });
      expect(h.backend.currentIndex, 1);
      expect(h.backend.position, const Duration(seconds: 60));
      expect(h.backend.playing, isFalse);
      final map = await client.command('coverage') as Map;
      expect(map['playedMs'], 10000);
      expect(((map['tracks'] as List)[1] as Map)['played'], isEmpty);
    },
  );

  test('invalid or stale map commands cannot move or pause playback', () async {
    await h.playback.play();
    await h.flush();
    for (final args in <Map<String, Object>>[
      {'bookId': 'old', 'filePath': '/map/0.mp3', 'positionMs': 0},
      {'bookId': 'map', 'filePath': '/missing.mp3', 'positionMs': 0},
      {'bookId': 'map', 'filePath': '/map/0.mp3', 'positionMs': -1},
      {'bookId': 'map', 'filePath': '/map/0.mp3', 'positionMs': 100001},
      {'bookId': 'map', 'filePath': '/map/0.mp3', 'positionMs': '20'},
    ]) {
      await expectLater(
        client.command('coverage-seek', args),
        throwsStateError,
      );
      expect(h.backend.position, Duration.zero);
      expect(h.backend.currentIndex, 0);
      expect(h.backend.playing, isTrue);
    }
    await expectLater(
      client.command('coverage', {'bookId': 42}),
      throwsStateError,
    );
  });
}
