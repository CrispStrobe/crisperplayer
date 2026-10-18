import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crisp_storage/crisp_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crisperplayer/cli/control_client.dart';
import 'package:crisperplayer/services/desktop_control_service.dart';
import 'package:crisperplayer/services/server/remote_library_service.dart';
import 'remote_library_test.dart' show MemoryCredentials;
import 'support/playback_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  RemoteConnection connection(
    String url, {
    bool encryption = true,
    String secret = 'fixture-password',
  }) => RemoteConnection(
    id: 'fixture',
    name: 'SMB',
    kind: 'smb',
    url: url,
    username: 'reader',
    secret: secret,
    requireEncryption: encryption,
  );

  test(
    'SMB connection validation, encryption default and credential redaction',
    () {
      final c = connection('smb://nas.local/Audio%20Books/');
      expect(c.requireEncryption, isTrue);
      expect(
        RemoteConnection.fromJson(
          c.toJson(credentials: true),
        ).requireEncryption,
        isTrue,
      );
      expect(c.toJson().containsKey('secret'), isFalse);
      for (final url in [
        'smb://nas.local/',
        'smb://user:password@nas.local/books/',
        'https://nas.local/books/',
        'smb://nas.local/books/?password=x',
        'smb://nas.local/books/%00/',
        'smb://nas.local/books/%2e%2e/',
      ]) {
        expect(() => connection(url), throwsFormatException, reason: url);
      }
      final session = SmbSession(c);
      expect(
        session.urlForPath('/A #1/Chapter %1.mp3'),
        'smb://nas.local/Audio%20Books/A%20%231/Chapter%20%251.mp3',
      );
      expect(() => session.urlForPath('../outside'), throwsFormatException);
      session.close();
    },
  );

  final python = Platform.environment['CRISPER_SMB_PYTHON'];
  test(
    'real SMB signed authentication, bounded streams, verified resume, changes and file operations',
    () async {
      final root = await Directory.systemTemp.createTemp('crisp_smb_');
      final folder = await Directory('${root.path}/Audio Books').create();
      final audio = Uint8List.fromList(
        List.generate(768 * 1024, (i) => i % 239),
      );
      final source = File('${folder.path}/Chapter #2.mp3');
      await source.writeAsBytes(audio);
      await File('${folder.path}/Chapter 10.mp3').writeAsBytes([1, 2, 3]);
      final config = File('.dart_tool/package_config.json').absolute;
      final packages =
          (jsonDecode(await config.readAsString()) as Map)['packages'] as List;
      final package = packages.cast<Map>().firstWhere(
        (p) => p['name'] == 'crisp_storage',
      );
      final fixture = config.uri
          .resolve('${package['rootUri']}/')
          .resolve('tool/smb_fixture.py');
      final process = await Process.start(python!, [
        File.fromUri(fixture).path,
        root.path,
      ]);
      final errors = <String>[];
      final stderr = process.stderr.transform(utf8.decoder).listen(errors.add);
      SmbSession? session;
      RemoteClient? client;
      try {
        final first = await process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first
            .timeout(const Duration(seconds: 15))
            .catchError(
              (Object e) => throw StateError(
                'SMB fixture could not start: ${errors.join()} ($e)',
              ),
            );
        final info = jsonDecode(first) as Map;
        final url = 'smb://127.0.0.1:${info['port']}/books/Audio%20Books/';
        // The fixture only offers SMB2: encryption must not silently downgrade.
        final encrypted = RemoteClient(connection(url));
        try {
          await expectLater(
            encrypted.browse(''),
            throwsA(isA<RemoteException>()),
          );
        } finally {
          encrypted.close();
        }
        final bad = RemoteClient(
          connection(url, encryption: false, secret: 'incorrect'),
        );
        try {
          await expectLater(bad.browse(''), throwsA(isA<RemoteException>()));
        } finally {
          bad.close();
        }
        final c = connection(url, encryption: false);
        client = RemoteClient(c);
        final tracks = await client.tracks('');
        expect(tracks.map((e) => e.name), ['Chapter #2.mp3', 'Chapter 10.mp3']);
        final output = File('${root.path}/download.mp3');
        final firstClient = client;
        await expectLater(
          firstClient.download(
            tracks.first.path,
            output,
            onBytes: (bytes) {
              if (bytes > 0) firstClient.close();
            },
          ),
          throwsA(isA<RemoteException>()),
        );
        final prefix = await output.length();
        expect(prefix, inExclusiveRange(0, audio.length));
        final progress = <int>[];
        client = RemoteClient(c);
        await client.download(tracks.first.path, output, onBytes: progress.add);
        expect(progress.first, prefix);
        expect(await output.readAsBytes(), audio);
        final stream = await client
            .downloadStream(tracks.first.path)
            .fold<BytesBuilder>(BytesBuilder(), (b, bytes) => b..add(bytes));
        expect(stream.takeBytes(), audio);
        await source.writeAsBytes(
          Uint8List.fromList(List.filled(audio.length, 42)),
        );
        // The Linux SMB fixture exposes whole-second modification times.
        // Make this a distinct remote revision even on a fast CI runner.
        await source.setLastModified(
          (await source.lastModified()).add(const Duration(seconds: 2)),
        );
        progress.clear();
        await client.download(tracks.first.path, output, onBytes: progress.add);
        expect(
          progress.first,
          0,
          reason: 'A changed source must restart instead of appending',
        );
        expect(await output.readAsBytes(), List.filled(audio.length, 42));
        await expectLater(
          client.download(tracks.first.path, output, limit: 10),
          throwsA(isA<RemoteException>()),
        );
        for (final path in [
          '/books/outside.mp3',
          'smb://another.invalid/books/Audio%20Books/a.mp3',
          '${url}bad%2fname.mp3',
        ]) {
          await expectLater(
            client.browse(path),
            throwsA(isA<RemoteException>()),
          );
        }
        session = SmbSession(c);
        final dir = session.urlForPath('New folder/');
        await session.mkdir(dir);
        final file = session.urlForPath('New folder/a.txt');
        await session.write(file, Uint8List.fromList([1, 2, 3]));
        expect((await session.stat(file))!.size, 3);
        final moved = session.urlForPath('New folder/b.txt');
        await session.rename(file, moved);
        await session.upload(
          moved,
          Stream.fromIterable([
            [4, 5],
            [6, 7],
          ]),
        );
        expect((await session.stat(moved))!.size, 4);
        await session.delete(moved, directory: false);
        await session.delete(dir, directory: true);
        expect(await session.stat(dir), isNull);
        await expectLater(
          session.delete(session.urlForPath('/'), directory: true),
          throwsA(isA<RemoteException>()),
        );
        client.close();
        await expectLater(client.browse(''), throwsA(isA<RemoteException>()));
        final h = PlaybackHarness();
        await h.init();
        final remote = RemoteLibraryService(
          h.library,
          credentials: MemoryCredentials(),
        );
        final descriptor = File('${h.root.path}/cli.json');
        final server = DesktopControlService(
          library: h.library,
          playback: h.playback,
          descriptor: descriptor,
          remote: remote,
        );
        await server.start();
        try {
          final control = ControlClient(descriptor);
          await control.command('server-connect', {
            'name': 'SMB fixture',
            'kind': 'smb',
            'url': url,
            'username': 'reader',
            'secret': 'fixture-password',
            'requireEncryption': false,
          });
          final connectionId = remote.connections.single.id;
          expect(
            jsonEncode(await control.command('servers')),
            isNot(contains('fixture-password')),
          );
          expect(remote.connections.single.requireEncryption, isFalse);
          final listing =
              await control.command('server-browse', {
                    'connectionId': connectionId,
                    'path': '',
                  })
                  as List;
          expect(listing, hasLength(2));
          final result =
              await control.command('server-download', {
                    'connectionId': connectionId,
                    'path': '',
                    'title': 'SMB book',
                  })
                  as Map;
          final book = (await h.db.getBook(result['bookId'] as String))!;
          final files = (jsonDecode(book.filePathsJson) as List).cast<String>();
          expect(files, hasLength(2));
          expect(
            await File(files.first).readAsBytes(),
            List.filled(audio.length, 42),
          );
          expect(
            (await h.db.select(h.db.remoteLinks).get()).single.serverUrl,
            url,
          );
          await control.command('server-disconnect', {
            'connectionId': connectionId,
          });
          expect(
            await File(files.first).exists(),
            isTrue,
            reason: 'Downloaded books remain available offline.',
          );
        } finally {
          await server.dispose();
          remote.dispose();
          await h.dispose();
        }
      } catch (e) {
        if (e is RemoteException) throw Exception('SMB diagnostic: ${e.cause}');
        rethrow;
      } finally {
        client?.close();
        session?.close();
        process.kill();
        await process.exitCode.timeout(const Duration(seconds: 10));
        await stderr.cancel();
        await root.delete(recursive: true);
      }
    },
    skip: python == null
        ? 'Set CRISPER_SMB_PYTHON to a Python with impacket installed.'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
