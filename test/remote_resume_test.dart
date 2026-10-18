import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crisperplayer/cli/control_client.dart';
import 'package:crisperplayer/services/desktop_control_service.dart';
import 'package:crisperplayer/services/server/download_state.dart';
import 'package:crisperplayer/services/server/remote_client.dart';
import 'package:crisperplayer/services/server/remote_library_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'remote_library_test.dart' show MemoryCredentials;
import 'support/playback_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  late HttpServer server;
  late Directory root;
  late String base, etag;
  late List<int> audio;
  late List<String?> ranges;
  late bool badRange, slow, weak;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('crisper_resume_');
    audio = List.generate(512 * 1024, (i) => i % 251);
    ranges = [];
    etag = '"v1"';
    badRange = false;
    slow = false;
    weak = false;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((request) async {
      try {
        if (request.method == 'PROPFIND') {
          request.response.statusCode = 207;
          request.response.write('<multistatus xmlns="DAV:"/>');
          await request.response.close();
          return;
        }
        final range = request.headers.value('range');
        ranges.add(range);
        var offset = 0;
        request.response.headers.set('etag', weak ? 'W/$etag' : etag);
        if (range != null && request.headers.value('if-range') == etag) {
          offset = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)![1]!);
          if (offset == audio.length) {
            request.response.statusCode = 416;
            request.response.headers.set(
              'content-range',
              'bytes */${audio.length}',
            );
            await request.response.close();
            return;
          }
          request.response.statusCode = 206;
          request.response.headers.set(
            'content-range',
            'bytes ${badRange ? offset + 1 : offset}-${audio.length - 1}/${audio.length}',
          );
        }
        request.response.headers.contentLength = audio.length - offset;
        for (var start = offset; start < audio.length; start += 8192) {
          request.response.add(
            audio.sublist(start, (start + 8192).clamp(0, audio.length)),
          );
          await request.response.flush();
          if (slow) await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        await request.response.close();
      } on IOException {
        /* Client paused the transfer. */
      } on StateError {
        /* Client paused the transfer. */
      }
    });
  });
  tearDown(() async {
    await server.close(force: true);
    await root.delete(recursive: true);
  });
  RemoteConnection connection() => RemoteConnection(
    id: 'test',
    name: 'NAS',
    kind: 'webdav',
    url: base,
    username: 'reader',
    secret: 'pass',
    allowLocalHttp: true,
  );
  Future<File> interrupted() async {
    slow = true;
    final output = File('${root.path}/book.mp3');
    final client = RemoteClient(connection());
    try {
      await expectLater(
        client.download(
          'book.mp3',
          output,
          onBytes: (bytes) {
            if (bytes > 0) throw StateError('Simulated interruption');
          },
        ),
        throwsStateError,
      );
    } finally {
      client.close();
    }
    expect(await output.length(), greaterThan(0));
    expect(await output.length(), lessThan(audio.length));
    return output;
  }

  test(
    'interrupted transfer resumes with Range/If-Range and produces exact bytes',
    () async {
      final output = await interrupted();
      final offset = await output.length();
      final client = RemoteClient(connection());
      addTearDown(client.close);
      await client.download('book.mp3', output);
      expect(ranges.last, 'bytes=$offset-');
      expect(await output.readAsBytes(), audio);
      await client.download('book.mp3', output);
      expect(ranges.last, 'bytes=${audio.length}-');
      expect(await output.readAsBytes(), audio);
    },
  );
  test('changed strong ETag restarts instead of appending old audio', () async {
    final output = await interrupted();
    etag = '"v2"';
    audio = List.filled(audio.length, 42);
    final client = RemoteClient(connection());
    addTearDown(client.close);
    await client.download('book.mp3', output);
    expect(await output.readAsBytes(), audio);
  });
  test('weak or absent validators restart from zero', () async {
    weak = true;
    final output = await interrupted();
    final client = RemoteClient(connection());
    addTearDown(client.close);
    await client.download('book.mp3', output);
    expect(ranges.last, isNull);
    expect(await output.readAsBytes(), audio);
  });
  test(
    'invalid resume ranges preserve the old partial instead of corrupting it',
    () async {
      final output = await interrupted();
      final bytes = await output.readAsBytes();
      badRange = true;
      final client = RemoteClient(connection());
      addTearDown(client.close);
      await expectLater(
        client.download('book.mp3', output),
        throwsA(isA<RemoteException>()),
      );
      expect(await output.readAsBytes(), bytes);
    },
  );
  test('a resume response cannot exceed the file size limit', () async {
    final output = await interrupted();
    final client = RemoteClient(connection());
    addTearDown(client.close);
    await expectLater(
      client.download('book.mp3', output, limit: audio.length - 1),
      throwsA(isA<RemoteException>()),
    );
  });
  test('corrupt sidecars and files from another URL restart safely', () async {
    final output = File('${root.path}/book.mp3');
    await output.writeAsBytes([9, 9]);
    await const DownloadState('other', '"v1"', 100).save(output);
    final client = RemoteClient(connection());
    addTearDown(client.close);
    await client.download('book.mp3', output);
    expect(ranges.last, isNull);
    expect(await output.readAsBytes(), audio);
    await File('${output.path}.resume').writeAsString('{bad');
    await client.download('book.mp3', output);
    expect(ranges.last, isNull);
  });
  test(
    'pause survives service restart, resume imports once, discard clears cached files',
    () async {
      final h = PlaybackHarness();
      await h.init();
      final store = MemoryCredentials();
      var service = RemoteLibraryService(h.library, credentials: store);
      try {
        await service.connect(
          name: 'NAS',
          kind: 'webdav',
          url: base,
          username: 'reader',
          secret: 'pass',
          allowLocalHttp: true,
        );
        slow = true;
        final paused = Completer<void>();
        service.addListener(() {
          if (service.downloadedBytes > 0 && !paused.isCompleted) {
            service.pauseDownload();
            paused.complete();
          }
        });
        final result = service.download(
          service.connections.single.id,
          'book.mp3',
          'My book',
          file: true,
        );
        await expectLater(result, throwsA(isA<RemoteException>()));
        expect(service.busy, isFalse);
        expect(service.downloads.single.phase, 'paused');
        final id = service.downloads.single.id;
        expect(await h.db.allBooks, isEmpty);
        service.dispose();
        service = RemoteLibraryService(h.library, credentials: store);
        await service.init();
        expect(service.downloads.single.id, id);
        expect(service.downloads.single.bytes, greaterThan(0));
        final imported = await service.resume(id);
        expect((await h.db.getBook(imported))!.title, 'My book');
        expect(service.downloads, isEmpty);
        expect(await h.db.allBooks, hasLength(1));
        expect(ranges.last, startsWith('bytes='));
        // Persist an interrupted second book and explicitly remove its cache.
        final done = Completer<void>();
        service.addListener(() {
          if (service.downloadedBytes > 0 && !done.isCompleted) {
            service.pauseDownload();
            done.complete();
          }
        });
        await expectLater(
          service.download(
            service.connections.single.id,
            'other.mp3',
            'Other',
            file: true,
          ),
          throwsA(isA<RemoteException>()),
        );
        await service.discard(service.downloads.single.id);
        expect(service.downloads, isEmpty);
        expect(
          await Directory('${h.root.path}/downloads').list().toList(),
          isEmpty,
        );
      } finally {
        service.dispose();
        await h.dispose();
      }
    },
  );
  test(
    'CLI can inspect and pause an in-flight blocking download without waiting for its queue',
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
        await cli.command('server-connect', {
          'name': 'NAS',
          'kind': 'webdav',
          'url': base,
          'username': 'reader',
          'secret': 'pass',
          'allowLocalHttp': true,
        });
        final ready = Completer<void>();
        slow = true;
        remote.addListener(() {
          if (remote.downloadedBytes > 0 && !ready.isCompleted) {
            ready.complete();
          }
        });
        final download = cli.command('server-download', {
          'connectionId': remote.connections.single.id,
          'path': 'book.mp3',
          'title': 'CLI book',
          'file': true,
        });
        final failure = expectLater(download, throwsStateError);
        await ready.future.timeout(const Duration(seconds: 5));
        final status = await cli.command('server-downloads') as Map;
        expect(status['downloading'], isTrue);
        await cli.command('server-cancel');
        await failure;
        expect(remote.downloads.single.phase, 'paused');
        final restored =
            await cli.command('server-resume', {
                  'downloadId': remote.downloads.single.id,
                })
                as Map;
        expect(restored['bookId'], isA<String>());
      } finally {
        await control.dispose();
        remote.dispose();
        await h.dispose();
      }
    },
  );
  test(
    'concurrent GUI/CLI connection writes retain both accounts in secure storage',
    () async {
      final h = PlaybackHarness();
      await h.init();
      final store = MemoryCredentials();
      final remote = RemoteLibraryService(h.library, credentials: store);
      try {
        await Future.wait([
          for (final name in ['One', 'Two'])
            remote.connect(
              name: name,
              kind: 'webdav',
              url: base,
              username: 'reader',
              secret: 'pass',
              allowLocalHttp: true,
            ),
        ]);
        expect(remote.connections, hasLength(2));
        expect(jsonDecode(store.value!) as List, hasLength(2));
      } finally {
        remote.dispose();
        await h.dispose();
      }
    },
  );
  test(
    'background CLI transfers leave playback commands responsive and transfer endpoint rejects other mutations',
    () async {
      final h = PlaybackHarness();
      await h.init();
      await h.book('keep', [60]);
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
        await cli.command('server-connect', {
          'name': 'NAS',
          'kind': 'webdav',
          'url': base,
          'username': 'reader',
          'secret': 'pass',
          'allowLocalHttp': true,
        });
        final config =
            jsonDecode(await control.descriptor.readAsString()) as Map;
        final http = HttpClient();
        try {
          final request = await http.postUrl(
            Uri.parse('http://127.0.0.1:${config['port']}/transfers'),
          );
          request.headers.set('authorization', 'Bearer ${config['token']}');
          request.write(jsonEncode({'command': 'delete', 'bookId': 'keep'}));
          final response = await request.close();
          expect(response.statusCode, 400);
          await response.drain<void>();
          expect(await h.db.getBook('keep'), isNotNull);
        } finally {
          http.close(force: true);
        }
        slow = true;
        final job =
            await cli.command('server-download', {
                  'connectionId': remote.connections.single.id,
                  'path': 'book.mp3',
                  'title': 'Background',
                  'file': true,
                  'background': true,
                })
                as Map;
        expect(job['id'], isA<String>());
        expect(job['phase'], 'downloading');
        await cli.command('play', {'bookId': 'keep'});
        expect(h.backend.playing, isTrue);
        await cli.command('pause');
        expect(h.backend.playing, isFalse);
        await cli.command('server-cancel');
        for (var i = 0; i < 100 && remote.busy; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(remote.downloads.single.phase, 'paused');
        await cli.command('server-discard', {'downloadId': job['id']});
        expect(remote.downloads, isEmpty);
      } finally {
        await control.dispose();
        remote.dispose();
        await h.dispose();
      }
    },
  );
  test(
    'queued NAS books download serially and queued cancellation never imports',
    () async {
      final h = PlaybackHarness();
      await h.init();
      final remote = RemoteLibraryService(
        h.library,
        credentials: MemoryCredentials(),
      );
      Future<void> until(bool Function() condition) async {
        final limit = DateTime.now().add(const Duration(seconds: 10));
        while (!condition()) {
          if (DateTime.now().isAfter(limit)) {
            throw StateError('Timed out waiting for download queue');
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }

      try {
        await remote.connect(
          name: 'NAS',
          kind: 'webdav',
          url: base,
          username: 'reader',
          secret: 'pass',
          allowLocalHttp: true,
        );
        slow = true;
        final connectionId = remote.connections.single.id;
        final first = await remote.startDownload(
          connectionId,
          'one.mp3',
          'One',
          file: true,
        );
        await until(() => remote.downloadedBytes > 0);
        final second = await remote.startDownload(
          connectionId,
          'two.mp3',
          'Two',
          file: true,
        );
        final removed = await remote.startDownload(
          connectionId,
          'three.mp3',
          'Three',
          file: true,
        );
        expect(first.phase, 'downloading');
        expect(second.phase, 'queued');
        expect(remote.status()['queuedDownloads'], 2);
        expect(ranges, hasLength(1));
        await expectLater(
          remote.startDownload(
            connectionId,
            'two.mp3',
            'Duplicate',
            file: true,
          ),
          throwsA(isA<RemoteException>()),
        );
        await remote.discard(removed.id);
        expect(remote.status()['queuedDownloads'], 1);
        await until(() => !remote.busy);
        expect(ranges, hasLength(2));
        expect(remote.downloads, isEmpty);
        expect((await h.db.allBooks).map((b) => b.title).toSet(), {
          'One',
          'Two',
        });
      } finally {
        remote.dispose();
        await h.dispose();
      }
    },
  );
}
