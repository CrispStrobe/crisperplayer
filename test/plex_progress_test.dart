import 'dart:convert';
import 'dart:io';
import 'package:crisperplayer/services/db/app_database.dart';
import 'package:crisperplayer/services/library_service.dart';
import 'package:crisperplayer/services/server/remote_library_service.dart';
import 'package:crisperplayer/services/sync/plex_progress_service.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'remote_library_test.dart' show MemoryCredentials;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late AppDatabase db;
  late Directory root;
  late RemoteLibraryService remote;
  late PlexProgressService sync;
  late HttpServer server;
  var offset = 0, writes = 0;
  var fail = false, open = false, mismatch = false;
  setUp(() async {
    offset = 0;
    writes = 0;
    fail = false;
    open = false;
    mismatch = false;
    root = await Directory.systemTemp.createTemp('crisper-sync-test-');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final library = LibraryService(db, storageDirectory: () async => root);
    await db
        .into(db.books)
        .insert(
          BooksCompanion.insert(
            id: 'book',
            title: 'Fixture',
            filePathsJson: jsonEncode(['/fixture.mp3']),
            addedAtMs: 0,
          ),
        );
    await db
        .into(db.bookTracks)
        .insert(
          BookTracksCompanion.insert(
            bookId: 'book',
            trackIndex: 0,
            filePath: '/fixture.mp3',
            durationMs: const Value(100000),
          ),
        );
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      expect(req.headers.value('X-Plex-Token'), 'fixture-token');
      if (fail) {
        req.response.statusCode = 503;
      } else if (req.uri.path == '/library/sections') {
        req.response.write(
          jsonEncode({
            'MediaContainer': {'Directory': []},
          }),
        );
      } else if (req.uri.path == '/library/metadata/1/children') {
        req.response.write(
          jsonEncode({
            'MediaContainer': {
              'Metadata': [
                {
                  'type': 'track',
                  'ratingKey': mismatch ? 'changed' : 'track1',
                  'duration': 100000,
                  'viewOffset': offset,
                  'index': 1,
                  'Media': [
                    {
                      'Part': [
                        {'key': '/media/one'},
                      ],
                    },
                  ],
                },
              ],
            },
          }),
        );
      } else if (req.uri.path == '/:/progress') {
        offset = int.parse(req.uri.queryParameters['time']!);
        writes++;
      } else if (req.uri.path != '/:/unscrobble') {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });
    remote = RemoteLibraryService(library, credentials: MemoryCredentials());
    await remote.connect(
      name: 'Plex fixture',
      kind: 'plex',
      url: 'http://127.0.0.1:${server.port}',
      secret: 'fixture-token',
      allowLocalHttp: true,
    );
    final connection = remote.connections.single;
    await db
        .into(db.remoteLinks)
        .insert(
          RemoteLinksCompanion.insert(
            bookId: 'book',
            serverUrl: connection.url.toString(),
            userId: 'plex:',
            itemId: 'library/metadata/1/children',
          ),
        );
    sync = PlexProgressService(library, remote, isBookOpen: (_) => open);
  });
  tearDown(() async {
    await sync.shutdown();
    remote.dispose();
    await db.close();
    await server.close(force: true);
    await root.delete(recursive: true);
  });
  Future<void> local(int ms) =>
      (db.update(db.books)..where((t) => t.id.equals('book'))).write(
        BooksCompanion(
          lastPositionFilePath: const Value('/fixture.mp3'),
          lastPositionMs: Value(ms),
          lastPlayedAtMs: const Value(10),
        ),
      );
  Future<void> enable() => sync.setEnabled(remote.connections.single.id, true);
  test('disabled sync does not transmit progress', () async {
    await local(4000);
    await sync.synchronize();
    expect(writes, 0);
    expect(offset, 0);
  });
  test(
    'pulls remote, pushes local and persists baseline across restart',
    () async {
      await enable();
      offset = 12000;
      await sync.synchronize();
      expect((await db.getBook('book'))!.lastPositionMs, 12000);
      await local(25000);
      await sync.synchronize();
      expect(offset, 25000);
      await sync.shutdown();
      sync = PlexProgressService(remote.library, remote);
      await sync.init();
      expect(sync.enabled, contains(remote.connections.single.id));
      offset = 30000;
      await sync.synchronize();
      expect((await db.getBook('book'))!.lastPositionMs, 30000);
    },
  );
  test('concurrent edits keep local data until an explicit choice', () async {
    await enable();
    await sync.synchronize();
    await local(20000);
    offset = 40000;
    await sync.synchronize();
    expect(sync.conflicts, contains('book'));
    expect(writes, 0);
    expect((await db.getBook('book'))!.lastPositionMs, 20000);
    await sync.synchronize(bookId: 'book', choice: 'local');
    expect(offset, 20000);
    expect(sync.conflicts, isEmpty);
  });
  test(
    'incoming changes never seek an open book; explicit remote applies once closed',
    () async {
      await enable();
      await sync.synchronize();
      open = true;
      offset = 15000;
      await sync.synchronize();
      expect((await db.getBook('book'))!.lastPositionMs, 0);
      expect(sync.issues, isNotEmpty);
      open = false;
      await sync.synchronize(bookId: 'book', choice: 'remote');
      expect((await db.getBook('book'))!.lastPositionMs, 15000);
    },
  );
  test(
    'offline errors retain dirty progress for retry and changed tracks refuse writes',
    () async {
      await enable();
      await sync.synchronize();
      await local(28000);
      fail = true;
      await sync.synchronize();
      expect(sync.issues, isNotEmpty);
      expect((await db.getBook('book'))!.lastPositionMs, 28000);
      fail = false;
      await sync.synchronize();
      expect(offset, 28000);
      mismatch = true;
      await local(35000);
      await sync.synchronize();
      expect(offset, 28000);
      expect(sync.issues, isNotEmpty);
    },
  );
}
