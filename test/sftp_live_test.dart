import 'dart:convert';
import 'dart:io';
import 'package:crisperplayer/services/server/remote_client.dart';
import 'package:crisperplayer/services/server/sftp_reader.dart';
import 'package:crisperplayer/services/server/remote_library_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'remote_library_test.dart' show MemoryCredentials;
import 'support/playback_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  final python = Platform.environment['CRISPER_SFTP_PYTHON'];
  test(
    'real SFTP host-key pinning, root confinement, natural ordering, pause/resume and offline import',
    () async {
      final h = PlaybackHarness();
      await h.init();
      final fixture = await Directory.systemTemp.createTemp('crisper_sftp_');
      final books = Directory('${fixture.path}/Audio Books');
      await books.create();
      final audio = List.generate(1024 * 1024, (i) => i % 239);
      await File('${books.path}/Chapter 10.mp3').writeAsBytes([1, 2, 3]);
      await File('${books.path}/Chapter 2.mp3').writeAsBytes(audio);
      await File('${fixture.path}/outside.mp3').writeAsBytes([8, 9]);
      await Link('${books.path}/outside-link').create('../outside.mp3');
      final process = await Process.start(python!, [
        'test/support/sftp_fixture.py',
        fixture.path,
      ]);
      final errors = <String>[];
      final errorSubscription = process.stderr
          .transform(utf8.decoder)
          .listen(errors.add);
      final first = await process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 15));
      final info = jsonDecode(first) as Map;
      final url = 'sftp://127.0.0.1:${info['port']}/Audio%20Books/';
      final pin = info['hostKey'] as String;
      RemoteConnection connection([String? hostKey]) => RemoteConnection(
        id: 's',
        name: 'SFTP',
        kind: 'sftp',
        url: url,
        username: 'reader',
        secret: 'fixture-password',
        hostKey: hostKey,
      );
      final remote = RemoteLibraryService(
        h.library,
        credentials: MemoryCredentials(),
      );
      try {
        // An untrusted key is rejected before credentials are sent.
        final unknown = RemoteClient(connection());
        await expectLater(
          unknown.browse(''),
          throwsA(
            isA<SftpHostKeyException>().having(
              (e) => e.fingerprint,
              'fingerprint',
              pin,
            ),
          ),
        );
        unknown.close();
        expect(await File('${fixture.path}/auth-count').exists(), isFalse);
        final client = RemoteClient(connection(pin));
        try {
          final listing = await client.browse('');
          expect(listing.any((e) => e.name == 'outside-link'), isFalse);
          final tracks = await client.tracks('');
          expect(tracks.map((e) => e.name), [
            'Chapter 2.mp3',
            'Chapter 10.mp3',
          ]);
          final output = File('${h.root.path}/partial.mp3');
          var interrupted = false;
          await expectLater(
            client.download(
              tracks.first.path,
              output,
              onBytes: (bytes) {
                if (bytes > 0 && !interrupted) {
                  interrupted = true;
                  throw StateError('Pause fixture');
                }
              },
            ),
            throwsStateError,
          );
          final prefix = await output.length();
          expect(prefix, greaterThan(0));
          expect(prefix, lessThan(audio.length));
          final progress = <int>[];
          await client.download(
            tracks.first.path,
            output,
            onBytes: progress.add,
          );
          expect(progress.first, prefix);
          expect(await output.readAsBytes(), audio);
          await expectLater(
            client.download('/outside.mp3', output),
            throwsA(isA<RemoteException>()),
          );
          await expectLater(
            client.download('${url}outside-link', output),
            throwsA(isA<RemoteException>()),
          );
        } finally {
          client.close();
        }
        await remote.connect(
          name: 'SFTP',
          kind: 'sftp',
          url: url,
          username: 'reader',
          secret: 'fixture-password',
          hostKey: pin,
        );
        final id = await remote.download(
          remote.connections.single.id,
          '',
          'SFTP book',
        );
        final book = (await h.db.getBook(id))!;
        final paths = (jsonDecode(book.filePathsJson) as List).cast<String>();
        expect(paths, hasLength(2));
        expect(await File(paths.first).readAsBytes(), audio);
        expect(
          (await h.db.select(h.db.remoteLinks).get()).single.serverUrl,
          url,
        );
        await h.db.importAllJson(await h.db.exportAllJson());
        final wrong = RemoteClient(
          connection('SHA256:${List.filled(43, 'A').join()}'),
        );
        await expectLater(
          wrong.browse(''),
          throwsA(isA<SftpHostKeyException>()),
        );
        wrong.close();
        final secretStatus = jsonEncode(remote.status());
        expect(secretStatus, isNot(contains('fixture-password')));
      } finally {
        remote.dispose();
        process.kill();
        await process.exitCode;
        await errorSubscription.cancel();
        await fixture.delete(recursive: true);
        await h.dispose();
      }
    },
    skip: python == null
        ? 'Set CRISPER_SFTP_PYTHON to a Python environment with paramiko for the isolated live SFTP fixture.'
        : false,
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
