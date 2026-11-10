import 'dart:io';

import 'package:crisperplayer/cli/control_client.dart';
import 'package:crisperplayer/services/desktop_control_service.dart';
import 'package:crisperplayer/services/return_trail_service.dart';
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
    await h.book('story', [180, 180]);
    await h.playback.loadBook('story');
    await h.playback.seekTrack(1, const Duration(seconds: 100));
    final store = ReturnTrailService(h.db);
    await store.record(
      bookId: 'story',
      filePath: '/story/0.mp3',
      startMs: 20000,
      endMs: 80000,
      heardAtMs: 1000,
    );
    await store.record(
      bookId: 'story',
      filePath: '/story/1.mp3',
      startMs: 40000,
      endMs: 100000,
      heardAtMs: 20000,
    );
    final descriptor = File('${h.root.path}/trail-cli.json');
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

  test('CLI exposes inspectable plan and exact protected return', () async {
    final plan = await client.command('trail-plan', {'seconds': 30}) as Map;
    expect(plan['requestedDurationMs'], 30000);
    expect((plan['anchor'] as Map)['positionMs'], 100000);
    expect(plan['clips'], hasLength(2));
    expect(h.playback.isReturnTrailActive, isFalse);

    final started = await client.command('trail-start', {'seconds': 30}) as Map;
    expect((started['returnTrail'] as Map)['active'], isTrue);
    expect(h.backend.playing, isTrue);
    await client.command('pause');
    final backup = await client.command('export') as Map;
    expect((backup['books'] as List).single['lastPositionMs'], 100000);
    expect(
      (backup['books'] as List).single['lastPositionFilePath'],
      '/story/1.mp3',
    );
    await client.command('trail-next');
    expect(h.playback.returnTrailClipIndex, 1);
    expect(h.backend.playing, isFalse);

    final returned = await client.command('trail-return') as Map;
    expect((returned['returnTrail'] as Map)['active'], isFalse);
    expect(h.backend.currentIndex, 1);
    expect(h.backend.position.inMilliseconds, 100000);
    expect(h.backend.playing, isFalse);
  });

  test(
    'CLI validates budgets and stale book actions without moving audio',
    () async {
      for (final seconds in [0, 301, '60']) {
        await expectLater(
          client.command('trail-start', {'seconds': seconds}),
          throwsStateError,
        );
      }
      await expectLater(
        client.command('trail-start', {'bookId': 'stale'}),
        throwsStateError,
      );
      expect(h.playback.isReturnTrailActive, isFalse);
      expect(h.backend.position.inMilliseconds, 100000);
      expect(await h.db.bookmarksFor('story'), isEmpty);
    },
  );

  test('CLI explicit continue adopts the reviewed position', () async {
    await client.command('trail-start');
    final clip = h.playback.returnTrailPlan!.clips.first;
    h.backend.move(Duration(milliseconds: clip.startMs + 1000));
    await client.command('trail-continue');
    expect(h.playback.isReturnTrailActive, isFalse);
    expect(h.backend.playing, isTrue);
    final saved = (await h.db.getBook('story'))!;
    expect(saved.lastPositionFilePath, clip.filePath);
    expect(saved.lastPositionMs, clip.startMs + 1000);
  });
}
