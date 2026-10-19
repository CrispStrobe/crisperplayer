@Tags(['live'])
@Timeout(Duration(minutes: 10))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:filen_client/filen_client.dart' as filen;
import 'package:internxt_client/internxt_client.dart' as internxt;
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';
import 'package:crisperplayer/services/db/app_database.dart';
import 'package:crisperplayer/services/library_service.dart';
import 'package:crisperplayer/services/server/remote_client.dart';
import 'package:crisperplayer/services/server/remote_library_service.dart';
import 'package:crisperplayer/services/sync/folder_progress_service.dart';
import '../remote_library_test.dart' show MemoryCredentials;
import '../support/audio_fixture.dart';

/// Credentials are injected only by scripts/live_cloud_tests.py on this Mac.
/// No .env file is loaded by the test or sent to GitHub.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  final enabled = Platform.environment['CRISPER_RUN_LIVE_CLOUD'] == '1';
  for (final kind in ['filen', 'internxt']) {
    test(
      '$kind real account: offline audio and two-device encrypted progress',
      () async {
        await runZoned(() async {
          final root = await Directory.systemTemp.createTemp(
            'crisper-live-$kind-',
          );
          final dbA = AppDatabase.forTesting(NativeDatabase.memory());
          final dbB = AppDatabase.forTesting(NativeDatabase.memory());
          final a = LibraryService(
            dbA,
            storageDirectory: () async =>
                Directory('${root.path}/a')..createSync(),
            probeDuration: (_) async => const Duration(seconds: 2),
          );
          final b = LibraryService(
            dbB,
            storageDirectory: () async =>
                Directory('${root.path}/b')..createSync(),
            probeDuration: (_) async => const Duration(seconds: 2),
          );
          final credentials = MemoryCredentials();
          final remoteA = RemoteLibraryService(a, credentials: credentials);
          final remoteB = RemoteLibraryService(
            b,
            credentials: MemoryCredentials(),
          );
          final syncA = FolderProgressService(
            a,
            remoteA,
            credentials: MemoryCredentials(),
          );
          final syncB = FolderProgressService(
            b,
            remoteB,
            credentials: MemoryCredentials(),
          );
          final folder = '/__crisperplayer_smoke_${const Uuid().v4()}';
          final audioName = 'Generated fixture ${const Uuid().v4()}.wav';
          filen.FilenClient? f;
          internxt.InternxtClient? i;
          var created = false;
          var stage = 'login';
          try {
            Zone.root.print('$kind live stage: $stage');
            await remoteA.connect(
              name: 'Disposable live fixture',
              kind: kind,
              url: RemoteConnection.cloudUrl(kind),
              username:
                  Platform.environment['CRISPER_${kind.toUpperCase()}_LOGIN']!,
              secret: Platform
                  .environment['CRISPER_${kind.toUpperCase()}_PASSWORD']!,
            );
            var connection = remoteA.connections.single;
            final auth = (jsonDecode(connection.secret) as Map)
                .cast<String, dynamic>();
            final fixture = await writeTestWav(
              File('${root.path}/fixture.wav'),
              seconds: 2,
            );
            final bytes = await fixture.readAsBytes();
            stage = 'create isolated fixture';
            Zone.root.print('$kind live stage: $stage');
            if (kind == 'filen') {
              f = filen.FilenClient(
                config: filen.ConfigService(
                  configPath: '${root.path}/sdk',
                  storage: filen.InMemoryConfigStorage(),
                ),
              )..setAuth(auth);
              final resolved = await f.createFolderRecursive(folder);
              created = true;
              await f.uploadBytes(bytes, audioName, resolved['uuid'] as String);
            } else {
              i = internxt.InternxtClient(
                config: internxt.ConfigService(
                  configPath: '${root.path}/sdk',
                  storage: internxt.InMemoryConfigStorage(),
                ),
              )..setAuth(auth);
              await i.createFolderPath(folder);
              created = true;
              await i.uploadFileBytes(bytes, audioName, folder);
            }
            if (kind == 'internxt') {
              stage = 'renew session and persist refreshed credentials';
              Zone.root.print('$kind live stage: $stage');
              final token = auth['newToken'] as String;
              final claims =
                  jsonDecode(
                        utf8.decode(
                          base64Url.decode(
                            base64Url.normalize(token.split('.')[1]),
                          ),
                        ),
                      )
                      as Map;
              final expires = DateTime.fromMillisecondsSinceEpoch(
                (claims['exp'] as num).toInt() * 1000,
              );
              final beforeRenewal = credentials.value;
              final refreshing = remoteA.createClient(
                connection,
                clock: () => expires.subtract(const Duration(seconds: 30)),
              );
              try {
                await refreshing.browse(folder);
              } finally {
                refreshing.close();
              }
              expect(
                credentials.value != beforeRenewal,
                isTrue,
                reason: 'Near-expiry session did not persist a renewal',
              );
              connection = remoteA.connections.single;
              i!.setAuth(
                (jsonDecode(connection.secret) as Map).cast<String, dynamic>(),
              );
            }
            stage = 'browse and offline import';
            Zone.root.print('$kind live stage: $stage');
            final client = remoteA.createClient(connection);
            try {
              final tracks = await client.tracks(folder);
              expect(tracks.map((e) => e.name), [audioName]);
            } finally {
              client.close();
            }
            final bookA = await remoteA.download(
              connection.id,
              folder,
              'Generated test book',
            );
            final rowA = (await a.getBook(bookA))!;
            final ownedA = AppDatabase.decodePaths(rowA.filePathsJson).single;
            expect(await File(ownedA).readAsBytes(), bytes);
            final bookB = (await b.importFiles([
              ownedA,
            ], title: 'Same audio on device B'))!;
            final rowB = (await b.getBook(bookB))!;
            final ownedB = AppDatabase.decodePaths(rowB.filePathsJson).single;
            final secondStore = remoteB.credentials as MemoryCredentials;
            secondStore.value = credentials.value;
            await remoteB.init();
            stage = 'encrypted progress round trip';
            Zone.root.print('$kind live stage: $stage');
            await syncA.configure(
              connectionId: connection.id,
              folder: folder,
              passphrase: 'Disposable live progress test passphrase',
            );
            await syncB.configure(
              connectionId: connection.id,
              folder: folder,
              passphrase: 'Disposable live progress test passphrase',
            );
            Future<void> position(
              LibraryService library,
              String id,
              String path,
              int milliseconds,
            ) => library.updateProgress(
              id,
              path,
              Duration(milliseconds: milliseconds),
              Duration(milliseconds: milliseconds),
              const Duration(seconds: 2),
            );
            await position(a, bookA, ownedA, 1000);
            await syncA.synchronize();
            expect(
              syncA.issues.isEmpty,
              isTrue,
              reason: 'Device A could not publish encrypted progress',
            );
            await syncB.synchronize();
            expect(
              syncB.issues.isEmpty,
              isTrue,
              reason: 'Device B could not read encrypted progress',
            );
            expect((await b.getBook(bookB))!.lastPositionMs, 1000);
            stage = 'concurrent edits and explicit conflict choice';
            Zone.root.print('$kind live stage: $stage');
            await position(a, bookA, ownedA, 1200);
            await position(b, bookB, ownedB, 1400);
            await syncA.synchronize();
            await syncB.synchronize();
            expect(syncB.issues.isEmpty, isTrue);
            final choices = syncB.conflicts[bookB]!;
            expect(choices.map((e) => e.positionMs).toSet(), {1200});
            expect((await b.getBook(bookB))!.lastPositionMs, 1400);
            await syncB.synchronize(resolveBookId: bookB, choice: 'local');
            await syncA.synchronize();
            expect(syncA.issues.isEmpty, isTrue);
            expect((await a.getBook(bookA))!.lastPositionMs, 1400);
            Zone.root.print('$kind live acceptance passed');
          } catch (error, stack) {
            if (stage.startsWith('renew session')) {
              final text = error.toString();
              final code = error is internxt.ApiException
                  ? '${error.statusCode}'
                  : RegExp(
                      r'Token refresh failed:.*?\b([1-5][0-9]{2})\b',
                    ).firstMatch(text)?.group(1);
              final categories = [
                'FormatException',
                'SocketException',
                'HandshakeException',
                'ClientException',
                'No valid credentials',
              ].where(text.contains).toList();
              Zone.root.print(
                'Renewal diagnostic: HTTP=$code; categories=$categories',
              );
              Zone.root.print(stack.toString().split('\n').take(2).join('\n'));
            }
            // The original exception may contain tokens, user filenames or account
            // details. Emit only its type and the app-owned stage.
            final libraryFrame = stack
                .toString()
                .split('\n')
                .firstWhere(
                  (line) => line.contains('package:crisperplayer/'),
                  orElse: () => '',
                );
            throw TestFailure(
              '$kind live $stage failed (${error.runtimeType}). $libraryFrame',
            );
          } finally {
            await syncA.shutdown();
            await syncB.shutdown();
            remoteA.dispose();
            remoteB.dispose();
            if (created) {
              try {
                if (f != null) {
                  await f.trashByPath(folder);
                } else {
                  await i!.deletePath(folder);
                }
                Zone.root.print(
                  '$kind disposable remote folder moved to trash',
                );
              } catch (error) {
                Zone.root.print(
                  '$kind cleanup failed (${error.runtimeType}); owned fixture: $folder',
                );
              }
            }
            await dbA.close();
            await dbB.close();
            await root.delete(recursive: true);
          }
        }, zoneSpecification: ZoneSpecification(print: (_, _, _, _) {}));
      },
      skip: enabled ? false : 'Local opt-in cloud credentials required',
    );
  }
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);
}
