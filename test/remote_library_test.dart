import 'package:crisperplayer/cli/control_client.dart';
import 'package:crisperplayer/services/desktop_control_service.dart';
import 'support/playback_harness.dart';
import 'dart:convert';
import 'dart:io';
import 'package:crisperplayer/services/server/credential_store.dart';
import 'package:crisperplayer/services/server/remote_client.dart';
import 'package:crisperplayer/services/server/remote_library_service.dart';
import 'package:crisperplayer/services/library_service.dart';
import 'package:crisperplayer/services/db/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryCredentials implements ServerCredentialStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late HttpServer server;
  late String base;
  late List<String> downloads;
  setUp(() async {
    downloads = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((request) async {
      final path = request.uri.path;
      if (path.startsWith('/dav/')) {
        expect(
          request.headers.value('authorization'),
          'Basic ${base64Encode(utf8.encode('reader:pass'))}',
        );
        if (request.method == 'PROPFIND') {
          expect(request.headers.value('depth'), '1');
          request.response.statusCode = 207;
          request.response.write('''<m:multistatus xmlns:m="DAV:">
<m:response><m:href>/dav/</m:href><m:propstat><m:prop><m:resourcetype><m:collection/></m:resourcetype></m:prop><m:status>HTTP/1.1 200 OK</m:status></m:propstat></m:response>
<m:response><m:href>/dav/02%20second.mp3</m:href><m:propstat><m:prop><m:displayname>02 second.mp3</m:displayname><m:getcontentlength>6</m:getcontentlength><m:resourcetype/></m:prop><m:status>HTTP/1.1 200 OK</m:status></m:propstat></m:response>
<m:response><m:href>/dav/01%20first.mp3</m:href><m:propstat><m:prop><m:displayname>01 first.mp3</m:displayname><m:resourcetype/></m:prop><m:status>HTTP/1.1 200 OK</m:status></m:propstat></m:response>
<m:response><m:href>/dav/sub/</m:href><m:propstat><m:prop><m:displayname>Subfolder &amp; more</m:displayname><m:resourcetype><m:collection/></m:resourcetype></m:prop><m:status>HTTP/1.1 200 OK</m:status></m:propstat></m:response>
<m:response><m:href>/dav/no.mp3</m:href><m:propstat><m:prop><m:displayname>Denied</m:displayname></m:prop><m:status>HTTP/1.1 403 Forbidden</m:status></m:propstat></m:response>
</m:multistatus>''');
        } else {
          downloads.add(path);
          request.response.add([1, 2, 3, 4, 5, 6]);
        }
      } else {
        expect(request.headers.value('X-Plex-Token'), 'plex-secret');
        expect(
          request.uri.queryParameters.containsKey('X-Plex-Token'),
          isFalse,
        );
        Object? result;
        if (path == '/library/sections') {
          result = {
            'Directory': [
              {'key': '1', 'type': 'artist', 'title': 'Audiobooks'},
              {'key': '2', 'type': 'movie', 'title': 'Films'},
            ],
          };
        } else if (path == '/library/sections/1/all') {
          final offset = request.uri.queryParameters['X-Plex-Container-Start'];
          result = {
            'totalSize': 2,
            'Metadata': [
              {
                'ratingKey': offset == '0' ? '10' : '11',
                'type': 'album',
                'title': offset == '0' ? 'Book A' : 'Book B',
                'parentTitle': 'Writer',
              },
            ],
          };
        } else if (path == '/library/metadata/10/children') {
          result = {
            'Metadata': [
              {
                'type': 'track',
                'index': 1,
                'parentIndex': 2,
                'title': 'Disc 2',
                'Media': [
                  {
                    'container': 'mp3',
                    'Part': [
                      {'key': '/media/two', 'file': '/audio/two.mp3'},
                    ],
                  },
                ],
              },
              {
                'type': 'track',
                'index': 1,
                'parentIndex': 1,
                'title': 'Disc 1',
                'Media': [
                  {
                    'container': 'mp3',
                    'Part': [
                      {'key': '/media/one', 'file': '/audio/one.mp3'},
                    ],
                  },
                ],
              },
            ],
          };
        } else if (path == '/unauthorized') {
          request.response.statusCode = 401;
        } else if (path == '/redirect') {
          request.response.statusCode = 302;
          request.response.headers.set('location', '$base/media/one');
        } else if (path.startsWith('/media/')) {
          downloads.add(path);
          request.response.add([1, 2, 3, 4, 5, 6]);
        } else if (path == '/empty') {
          /* empty */
        } else {
          request.response.statusCode = 404;
        }
        if (result != null) {
          request.response.write(jsonEncode({'MediaContainer': result}));
        }
      }
      await request.response.close();
    });
  });
  tearDown(() => server.close(force: true));
  RemoteConnection plex() => RemoteConnection(
    id: 'p',
    name: 'Plex',
    kind: 'plex',
    url: base,
    secret: 'plex-secret',
    allowLocalHttp: true,
  );
  test(
    'connection validates URLs, local HTTP and never exports credentials',
    () {
      for (final url in [
        'http://example.com',
        'https://user:pass@example.com',
        'https://example.com/?token=secret',
      ]) {
        expect(
          () => RemoteConnection(
            id: 'x',
            name: 'x',
            kind: 'plex',
            url: url,
            secret: 'x',
            allowLocalHttp: true,
          ),
          throwsFormatException,
        );
      }
      expect(
        () => RemoteConnection(
          id: 'x',
          name: 'x',
          kind: 'plex',
          url: base,
          secret: 'x',
        ),
        throwsFormatException,
      );
      expect(jsonEncode(plex().toJson()), isNot(contains('plex-secret')));
      expect(RemoteConnection.isLocalHost('192.168.1.2'), isTrue);
      expect(RemoteConnection.isLocalHost('172.32.1.2'), isFalse);
      expect(RemoteConnection.isLocalHost('fd00::1'), isTrue);
    },
  );
  test('server media URLs cannot escape connection or carry credentials', () {
    final connection = RemoteConnection(
      id: 'x',
      name: 'x',
      kind: 'webdav',
      url: 'https://example.com/dav/',
      secret: 'x',
    );
    final client = RemoteClient(connection);
    addTearDown(client.close);
    for (final path in [
      'https://evil.example/dav/a.mp3',
      '//evil.example/a.mp3',
      '/other/a.mp3',
      '/dav/%2e%2e/secret',
      '/dav/a?X-Plex-Token=x',
    ]) {
      expect(
        () => client.uri(path),
        throwsA(anyOf(isA<RemoteException>(), isA<FormatException>())),
      );
    }
    expect(client.uri('/dav/Chapter%201.mp3').path, '/dav/Chapter%201.mp3');
  });
  test(
    'Plex filters music, paginates albums and orders tracks by disc and index',
    () async {
      final client = RemoteClient(plex());
      addTearDown(client.close);
      final sections = await client.browse('');
      expect(sections.single.name, 'Audiobooks');
      final books = await client.browse(sections.single.path);
      expect(books.map((b) => b.name), ['Book A', 'Book B']);
      expect(books.first.author, 'Writer');
      expect((await client.tracks(books.first.path)).map((t) => t.path), [
        '/media/one',
        '/media/two',
      ]);
    },
  );
  test(
    'authentication, redirects, empty files and limits fail explicitly',
    () async {
      final client = RemoteClient(plex());
      addTearDown(client.close);
      final dir = await Directory.systemTemp.createTemp('remote_failure_');
      addTearDown(() => dir.delete(recursive: true));
      for (final path in ['unauthorized', 'redirect', 'empty']) {
        await expectLater(
          client.download(path, File('${dir.path}/file')),
          throwsA(isA<RemoteException>()),
        );
      }
      await expectLater(
        client.download('media/one', File('${dir.path}/file'), limit: 2),
        throwsA(isA<RemoteException>()),
      );
      expect(downloads, ['/media/one']);
    },
  );
  test(
    'WebDAV parses namespaces, escaped filenames, successful properties and folders',
    () async {
      final client = RemoteClient(
        RemoteConnection(
          id: 'd',
          name: 'NAS',
          kind: 'webdav',
          url: '$base/dav/',
          username: 'reader',
          secret: 'pass',
          allowLocalHttp: true,
        ),
      );
      addTearDown(client.close);
      final rows = await client.browse('');
      expect(rows.map((e) => e.name), [
        'Subfolder & more',
        '01 first.mp3',
        '02 second.mp3',
      ]);
      expect(rows.first.type, 'folder');
      expect((await client.tracks('$base/dav/')).map((e) => e.name), [
        '01 first.mp3',
        '02 second.mp3',
      ]);
      expect(rows.last.size, 6);
    },
  );
  test(
    'download imports owned ordered tracks, persists identity and avoids duplicates after reconnect',
    () async {
      final dir = await Directory.systemTemp.createTemp('remote_library_');
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final library = LibraryService(
        db,
        storageDirectory: () async => dir,
        probeDuration: (_) async => const Duration(seconds: 12),
      );
      final store = MemoryCredentials();
      final service = RemoteLibraryService(library, credentials: store);
      try {
        await service.connect(
          name: 'Plex',
          kind: 'plex',
          url: base,
          secret: 'plex-secret',
          allowLocalHttp: true,
        );
        final connection = service.connections.single;
        final id = await service.download(
          connection.id,
          'library/metadata/10/children',
          'Book A',
          author: 'Writer',
        );
        expect(downloads, ['/media/one', '/media/two']);
        final book = (await library.getBook(id))!;
        expect(book.title, 'Book A');
        expect(book.author, 'Writer');
        expect(book.totalDurationMs, 24000);
        final paths = (jsonDecode(book.filePathsJson) as List).cast<String>();
        expect(paths.every((path) => path.startsWith(dir.path)), isTrue);
        expect(await File(paths.first).readAsBytes(), [1, 2, 3, 4, 5, 6]);
        expect(jsonEncode(service.status()), isNot(contains('plex-secret')));
        expect(
          jsonEncode(await db.exportAllJson()),
          isNot(contains('plex-secret')),
        );
        final backup = await db.exportAllJson();
        await db.importAllJson(backup);
        expect(await db.select(db.remoteLinks).get(), hasLength(1));
        await service.disconnect(connection.id);
        await service.connect(
          name: 'Again',
          kind: 'plex',
          url: base,
          secret: 'plex-secret',
          allowLocalHttp: true,
        );
        expect(
          await service.download(
            service.connections.single.id,
            'library/metadata/10/children',
            'Book A',
          ),
          id,
        );
        expect(downloads, hasLength(2));
        final restored = RemoteLibraryService(library, credentials: store);
        await restored.init();
        expect(restored.connections.single.name, 'Again');
        restored.dispose();
        await library.deleteBook(id);
        expect(await db.select(db.remoteLinks).get(), isEmpty);
      } finally {
        service.dispose();
        await db.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'failed remote import leaves no partial book and releases busy state',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'remote_failed_library_',
      );
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final service = RemoteLibraryService(
        LibraryService(db, storageDirectory: () async => dir),
        credentials: MemoryCredentials(),
      );
      try {
        await service.connect(
          name: 'Plex',
          kind: 'plex',
          url: base,
          secret: 'plex-secret',
          allowLocalHttp: true,
        );
        await expectLater(
          service.download(
            service.connections.single.id,
            'empty',
            'Broken',
            file: true,
          ),
          throwsA(isA<RemoteException>()),
        );
        expect(service.busy, isFalse);
        expect(await db.allBooks, isEmpty);
      } finally {
        service.dispose();
        await db.close();
        await dir.delete(recursive: true);
      }
    },
  );

  test(
    'CLI connects, lists, browses, downloads and disconnects without exposing credentials',
    () async {
      final h = PlaybackHarness();
      await h.init();
      final remote = RemoteLibraryService(
        h.library,
        credentials: MemoryCredentials(),
      );
      final control = DesktopControlService(
        library: h.library,
        playback: h.playback,
        descriptor: File('${h.root.path}/cli.json'),
        remote: remote,
      );
      try {
        await control.start();
        final cli = ControlClient(control.descriptor);
        final connected =
            await cli.command('server-connect', {
                  'name': 'CLI Plex',
                  'kind': 'plex',
                  'url': base,
                  'secret': 'plex-secret',
                  'allowLocalHttp': true,
                })
                as Map;
        expect(jsonEncode(connected), isNot(contains('plex-secret')));
        final id = (connected['connections'] as List).single['id'] as String;
        final sections =
            await cli.command('server-browse', {'connectionId': id}) as List;
        expect(sections.single['name'], 'Audiobooks');
        final result =
            await cli.command('server-download', {
                  'connectionId': id,
                  'path': 'library/metadata/10/children',
                  'title': 'CLI book',
                  'author': 'Writer',
                })
                as Map;
        expect(
          (await h.library.getBook(result['bookId'] as String))!.title,
          'CLI book',
        );
        await cli.command('server-disconnect', {'connectionId': id});
        expect((await cli.command('servers') as Map)['connections'], isEmpty);
        expect(await h.db.allBooks, hasLength(1));
      } finally {
        await control.dispose();
        remote.dispose();
        await h.dispose();
      }
    },
  );
}
