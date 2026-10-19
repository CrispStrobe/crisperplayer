import 'dart:async';
import 'package:crisperplayer/cli/control_client.dart';
import 'package:crisperplayer/services/desktop_control_service.dart';
import 'dart:convert';
import 'dart:io';
import 'package:crisperplayer/services/db/app_database.dart';
import 'package:crisperplayer/services/server/remote_library_service.dart';
import 'package:crisperplayer/services/sync/folder_progress_service.dart';
import 'package:crisperplayer/services/sync/progress_record.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'remote_library_test.dart' show MemoryCredentials;
import 'support/playback_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  // These simulated devices deliberately use separate NativeDatabase.memory executors.
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);
  late HttpServer server;
  late PlaybackHarness a, b;
  late RemoteLibraryService ra, rb;
  late FolderProgressService sa, sb;
  late MemoryCredentials ca, cb;
  final files = <String, List<int>>{};
  var offline = false, openB = false;
  Completer<void>? holdListings, listingStarted;
  Future<FolderProgressService> device(
    PlaybackHarness h,
    MemoryCredentials store,
    void Function(RemoteLibraryService) save, {
    bool second = false,
  }) async {
    final audio = File('${h.root.path}/different-local-name.mp3');
    await audio.writeAsBytes(List.generate(1024, (i) => i % 251));
    await h.db
        .into(h.db.books)
        .insert(
          BooksCompanion.insert(
            id: 'book',
            title: 'Private title',
            filePathsJson: jsonEncode([audio.path]),
            addedAtMs: 0,
            totalDurationMs: const Value(100000),
          ),
        );
    await h.db
        .into(h.db.bookTracks)
        .insert(
          BookTracksCompanion.insert(
            bookId: 'book',
            trackIndex: 0,
            filePath: audio.path,
            durationMs: const Value(100000),
          ),
        );
    final remote = RemoteLibraryService(
      h.library,
      credentials: MemoryCredentials(),
    );
    save(remote);
    await remote.connect(
      name: 'DAV fixture',
      kind: 'webdav',
      url: 'http://127.0.0.1:${server.port}/dav/',
      username: 'reader',
      secret: 'fixture',
      allowLocalHttp: true,
    );
    final service = FolderProgressService(
      h.library,
      remote,
      credentials: store,
      isBookOpen: (_) => second && openB,
    );
    await service.configure(
      connectionId: remote.connections.single.id,
      folder: '/dav/sync/',
      passphrase: 'correct shared test passphrase',
    );
    return service;
  }

  Future<void> move(PlaybackHarness h, int ms) async {
    final track = (await h.db.tracksFor('book')).single;
    await h.library.updateProgress(
      'book',
      track.filePath,
      Duration(milliseconds: ms),
      Duration(milliseconds: ms),
      const Duration(seconds: 100),
    );
  }

  setUp(() async {
    holdListings = null;
    listingStarted = null;
    files.clear();
    offline = false;
    openB = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      expect(
        req.headers.value('authorization'),
        'Basic ${base64Encode(utf8.encode('reader:fixture'))}',
      );
      final path = req.uri.path;
      final hold = holdListings;
      if (req.method == 'PROPFIND' && hold != null) {
        if (listingStarted?.isCompleted == false) listingStarted!.complete();
        await hold.future;
      }
      if (offline) {
        req.response.statusCode = 503;
      } else if (req.method == 'PROPFIND') {
        req.response.statusCode = 207;
        final rows = files.keys
            .where((k) => k.startsWith(path))
            .map(
              (k) =>
                  '<d:response><d:href>$k</d:href><d:propstat><d:prop><d:resourcetype/><d:getcontentlength>${files[k]!.length}</d:getcontentlength></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>',
            )
            .join();
        req.response.write(
          '<d:multistatus xmlns:d="DAV:"><d:response><d:href>$path</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>$rows</d:multistatus>',
        );
      } else if (req.method == 'PUT') {
        files[path] = await req.fold<List<int>>([], (a, b) => a..addAll(b));
        req.response.statusCode = 201;
      } else if (req.method == 'DELETE') {
        files.remove(path);
        req.response.statusCode = 204;
      } else if (files.containsKey(path)) {
        req.response.contentLength = files[path]!.length;
        req.response.headers.set('etag', '"${files[path]!.length}"');
        req.response.add(files[path]!);
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });
    a = PlaybackHarness();
    b = PlaybackHarness();
    await a.init();
    await b.init();
    ca = MemoryCredentials();
    cb = MemoryCredentials();
    sa = await device(a, ca, (r) => ra = r);
    sb = await device(b, cb, (r) => rb = r, second: true);
  });
  tearDown(() async {
    await sa.shutdown();
    await sb.shutdown();
    ra.dispose();
    rb.dispose();
    await a.dispose();
    await b.dispose();
    await server.close(force: true);
  });
  test(
    'encrypted progress matches audio content across local paths, with no audio or titles uploaded',
    () async {
      await move(a, 12000);
      await sa.synchronize();
      expect(sa.issues, isEmpty);
      expect(files, isNotEmpty);
      for (final bytes in files.values) {
        final text = utf8.decode(bytes);
        expect(text, contains('crisperplayer-progress-v1'));
        expect(text, isNot(contains('Private title')));
        expect(text, isNot(contains('positionMs')));
      }
      await sb.synchronize();
      expect(sb.issues, isEmpty);
      expect((await b.db.getBook('book'))!.lastPositionMs, 12000);
      await move(b, 27000);
      await sb.synchronize();
      await sa.synchronize();
      expect((await a.db.getBook('book'))!.lastPositionMs, 27000);
    },
  );
  test(
    'simultaneous offline progress produces a conflict and explicit choice converges',
    () async {
      await move(a, 10000);
      await sa.synchronize();
      await sb.synchronize();
      await move(a, 20000);
      await move(b, 40000);
      await sa.synchronize();
      await sb.synchronize();
      expect(sb.conflicts['book'], isNotEmpty);
      expect((await b.db.getBook('book'))!.lastPositionMs, 40000);
      final choice = FolderProgressService.candidateId(
        sb.conflicts['book']!.first,
      );
      await sb.synchronize(resolveBookId: 'book', choice: choice);
      expect(sb.issues, isEmpty);
      expect(sb.conflicts, isEmpty);
      expect((await b.db.getBook('book'))!.lastPositionMs, 20000);
      await sa.synchronize();
      expect(sa.conflicts, isEmpty);
      expect((await a.db.getBook('book'))!.lastPositionMs, 20000);
    },
  );
  test(
    'wrong passphrase cannot read, apply or overwrite existing progress',
    () async {
      await move(a, 23000);
      await sa.synchronize();
      final original = Map<String, List<int>>.from(files);
      await sb.configure(
        connectionId: rb.connections.single.id,
        folder: '/dav/sync/',
        passphrase: 'a different incorrect password',
      );
      await sb.synchronize();
      expect(sb.issues, isNotEmpty);
      expect(files, original);
      expect((await b.db.getBook('book'))!.lastPositionMs, 0);
    },
  );
  test(
    'offline dirty progress survives restart and open books reject remote seeks',
    () async {
      await move(a, 15000);
      offline = true;
      await sa.synchronize();
      expect(sa.issues, isNotEmpty);
      await sa.shutdown();
      sa = FolderProgressService(a.library, ra, credentials: ca);
      offline = false;
      await sa.synchronize();
      expect(sa.issues, isEmpty);
      openB = true;
      await sb.synchronize();
      expect((await b.db.getBook('book'))!.lastPositionMs, 0);
      openB = false;
      await sb.synchronize();
      expect((await b.db.getBook('book'))!.lastPositionMs, 15000);
    },
  );
  test(
    'snapshot retention deletes only this device old metadata and keeps both devices latest',
    () async {
      for (final position in [1000, 2000, 3000, 4000]) {
        await move(a, position);
        await sa.synchronize();
      }
      expect(files.length, 2);
      await sb.synchronize();
      expect(files.length, 3);
      await move(a, 6000);
      await sa.synchronize();
      expect(files.length, 3);
    },
  );
  test(
    'authenticated CLI controls the same folder sync and keeps the passphrase out of status',
    () async {
      final descriptor = File('${a.root.path}/cli.json');
      final control = DesktopControlService(
        library: a.library,
        playback: a.playback,
        descriptor: descriptor,
        remote: ra,
        folderSync: sa,
      );
      await control.start();
      try {
        final client = ControlClient(descriptor);
        expect(
          (await client.command('folder-sync-status') as Map)['enabled'],
          true,
        );
        await move(a, 18000);
        await client.command('folder-sync-now');
        await sb.synchronize();
        expect((await b.db.getBook('book'))!.lastPositionMs, 18000);
        final status = jsonEncode(await client.command('folder-sync-status'));
        expect(status, isNot(contains('correct shared test passphrase')));
        await client.command('folder-sync-configure', {});
        expect(sa.enabled, isFalse);
      } finally {
        await control.dispose();
      }
    },
  );
  test('slow sync does not delay authenticated pause commands', () async {
    final control = DesktopControlService(
      library: a.library,
      playback: a.playback,
      descriptor: File('${a.root.path}/responsive-cli.json'),
      remote: ra,
      folderSync: sa,
    );
    await control.start();
    final client = ControlClient(control.descriptor);
    try {
      await client.command('play', {'bookId': 'book'});
      a.backend.move(const Duration(seconds: 18));
      await a.flush();
      holdListings = Completer<void>();
      listingStarted = Completer<void>();
      final syncing = client.command('folder-sync-now');
      await listingStarted!.future.timeout(const Duration(seconds: 5));
      await client.command('pause').timeout(const Duration(seconds: 2));
      expect(a.backend.playing, isFalse);
      holdListings!.complete();
      await syncing;
    } finally {
      if (holdListings?.isCompleted == false) holdListings!.complete();
      await control.dispose();
    }
  });
  test(
    'vector clocks preserve concurrency and explicit merging dominates both branches',
    () {
      const first = ProgressRecord({'a': 1}, 0, 1000, [10000]);
      final left = first.change('a', 0, 2000, [10000]),
          right = first.change('b', 0, 3000, [10000]);
      expect(left.dominates(right), isFalse);
      expect(right.dominates(left), isFalse);
      final resolved = left.change('a', 0, 3000, [10000], right);
      expect(resolved.dominates(left), isTrue);
      expect(resolved.dominates(right), isTrue);
      expect(
        () => ProgressRecord.fromJson({
          'clock': {'a': 1},
          'index': 0,
          'positionMs': 12000,
          'durations': [10000],
        }),
        throwsFormatException,
      );
    },
  );
}
