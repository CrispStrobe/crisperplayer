// Live SMB3 qualification of both SMB backends against a real server.
//
// Skipped unless CRISPER_SMB3_URL is set, e.g.
//   CRISPER_SMB3_URL=smb://127.0.0.1:1445/Books/
//   CRISPER_SMB3_USER=reader CRISPER_SMB3_SECRET=fixture-password
//   CRISPER_SMB3_BIG_SHA256=<sha256 of big.bin>          (optional)
//   CRISPER_SMB3_PLAIN_URL=smb://127.0.0.1:1446/Books/   (optional server
//     WITHOUT encryption, to prove that required encryption is refused)
//   CRISPER_SMB3_DENIED_URL=smb://127.0.0.1:1445/Other/  (optional share the
//     user may not access)
//   CRISP_SMB_LIBRARY=/abs/path/libcrisp_smb_bridge.dylib (host Rust bridge;
//     omit in app builds that bundle it)
//   CRISPER_SMB3_EXPECT_BUNDLED=true  (assert the app-bundled bridge loaded)
//   CRISPER_SMB3_BACKENDS=libsmb2,rust                   (default: both)
//
// On iOS/macOS apps run integration_test/smb3_backend_qualification_test.dart
// with the same names as --dart-define values.
//
// The server should require SMB3, signing and encryption. The share must
// contain `big.bin` and `A #1/Chapter 1.mp3`; every other file is created
// under a unique scratch folder per backend and removed afterwards.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_storage/crisp_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const _defines = {
  'CRISPER_SMB3_URL': String.fromEnvironment('CRISPER_SMB3_URL'),
  'CRISPER_SMB3_USER': String.fromEnvironment('CRISPER_SMB3_USER'),
  'CRISPER_SMB3_SECRET': String.fromEnvironment('CRISPER_SMB3_SECRET'),
  'CRISPER_SMB3_BIG_SHA256': String.fromEnvironment('CRISPER_SMB3_BIG_SHA256'),
  'CRISPER_SMB3_PLAIN_URL': String.fromEnvironment('CRISPER_SMB3_PLAIN_URL'),
  'CRISPER_SMB3_DENIED_URL': String.fromEnvironment('CRISPER_SMB3_DENIED_URL'),
  'CRISPER_SMB3_BACKENDS': String.fromEnvironment('CRISPER_SMB3_BACKENDS'),
  'CRISPER_SMB3_EXPECT_BUNDLED': String.fromEnvironment(
    'CRISPER_SMB3_EXPECT_BUNDLED',
  ),
};

void main() {
  // --dart-define wins (iOS simulators/devices do not see the host
  // environment); otherwise fall back to process environment variables.
  final env = {
    ...Platform.environment,
    for (final e in _defines.entries)
      if (e.value.isNotEmpty) e.key: e.value,
  };
  final url = env['CRISPER_SMB3_URL'];
  final skip = url == null
      ? 'Set CRISPER_SMB3_URL to run live SMB3 checks.'
      : null;
  String? needs(String key) =>
      skip ?? (env[key] == null ? 'Set $key for this check.' : null);
  final backends = (env['CRISPER_SMB3_BACKENDS'] ?? 'libsmb2,rust')
      .split(',')
      .map((b) => parseSmbBackend(b.trim())!)
      .toList();
  final stamp = DateTime.now().millisecondsSinceEpoch;
  const big = '/big.bin';
  const chapter = '/A #1/Chapter 1.mp3';

  RemoteConnection connection(
    String target, {
    String? secret,
    bool encryption = true,
    required SmbBackend backend,
  }) => RemoteConnection(
    id: 'smb3-qualification',
    name: 'SMB3',
    kind: 'smb',
    url: target,
    username: env['CRISPER_SMB3_USER'] ?? 'reader',
    secret: secret ?? env['CRISPER_SMB3_SECRET'] ?? 'fixture-password',
    requireEncryption: encryption,
    smbBackend: backend,
  );

  final sessions = <SmbSession>[];
  SmbSession open(
    SmbBackend backend, {
    String? target,
    String? secret,
    bool encryption = true,
  }) {
    final s = SmbSession(
      connection(
        target ?? url!,
        secret: secret,
        encryption: encryption,
        backend: backend,
      ),
    );
    sessions.add(s);
    return s;
  }

  tearDown(() {
    for (final s in sessions) {
      s.close();
    }
    sessions.clear();
  });

  Future<Uint8List> readAll(SmbSession s, String path) async {
    final b = BytesBuilder(copy: false);
    await for (final c in s.stream(s.urlForPath(path))) {
      b.add(c);
    }
    return b.takeBytes();
  }

  Future<void> removeTree(SmbSession s, String path) async {
    final entry = await s.stat(s.urlForPath(path));
    if (entry == null) return;
    if (entry.type == 'folder') {
      for (final child in await s.browse(s.urlForPath(path))) {
        await removeTree(s, '$path/${child.name}');
      }
      await s.delete(s.urlForPath(path), directory: true);
    } else {
      await s.delete(s.urlForPath(path), directory: false);
    }
  }

  Uint8List pattern(int length, [int seed = 7]) =>
      Uint8List.fromList(List.generate(length, (i) => (i * 31 + seed) % 256));

  Matcher remoteError([RemoteErrorCode? code]) => throwsA(
    isA<RemoteException>().having(
      (e) => code == null || e.code == code,
      'code ${code?.name}',
      isTrue,
    ),
  );

  for (final backend in backends) {
    final scratch = '/q-${backend.name}-$stamp';
    group('SMB3 ${backend.name}', () {
      setUpAll(() async {
        if (skip != null) return;
        final s = SmbSession(connection(url!, backend: backend));
        try {
          await removeTree(s, scratch);
          await s.mkdir(s.urlForPath(scratch));
        } finally {
          s.close();
        }
      });
      tearDownAll(() async {
        if (skip != null) return;
        final s = SmbSession(connection(url!, backend: backend));
        try {
          await removeTree(s, scratch);
        } finally {
          s.close();
        }
      });

      // --- Selection and discovery -------------------------------------
      test('uses exactly the requested backend', () async {
        final s = open(backend);
        await s.browse(s.urlForPath('/'));
        expect(s.effectiveBackend, backend);
        if (backend == SmbBackend.rust) {
          final where = rustSmbLibraryLocation;
          // ignore: avoid_print
          print('[rust] bridge loaded from $where');
          expect(where, isNotNull);
          if (env['CRISPER_SMB3_EXPECT_BUNDLED'] == 'true') {
            expect(where, isNot('default'));
            expect(where, isNot(env['CRISP_SMB_LIBRARY']));
            expect(where, contains('crisp_smb_bridge'));
          }
        }
      }, skip: skip);

      test('browse lists folders first, then files by name', () async {
        final s = open(backend);
        final entries = await s.browse(s.urlForPath('/'));
        final names = entries.map((e) => e.name).toList();
        expect(names, containsAll(['big.bin', 'A #1']));
        final firstFile = entries.indexWhere((e) => e.type == 'file');
        final lastFolder = entries.lastIndexWhere((e) => e.type == 'folder');
        expect(lastFolder, lessThan(firstFile));
        expect(entries.every((e) => e.path.startsWith(url!)), isTrue);
      }, skip: skip);

      test('stat reports files, folders and missing paths', () async {
        final s = open(backend);
        final file = await s.stat(s.urlForPath(big));
        expect(file!.type, 'file');
        expect(file.size, greaterThan(1024 * 1024));
        final folder = await s.stat(s.urlForPath('/A #1'));
        expect(folder!.type, 'folder');
        expect(await s.stat(s.urlForPath('/does-not-exist.bin')), isNull);
        expect(await s.stat(s.urlForPath('/no/such/dir/x.bin')), isNull);
      }, skip: skip);

      // --- Reads ----------------------------------------------------------
      test(
        'downloads a large file byte-exactly with monotonic progress',
        () async {
          final s = open(backend);
          final dir = await Directory.systemTemp.createTemp('smb3-q');
          try {
            final out = File('${dir.path}/big.bin');
            final size = (await s.stat(s.urlForPath(big)))!.size!;
            final progress = <int>[];
            final watch = Stopwatch()..start();
            await s.download(
              s.urlForPath(big),
              out,
              onBytes: progress.add,
              limit: size,
            );
            watch.stop();
            expect(await out.length(), size);
            expect(progress.last, size);
            for (var i = 1; i < progress.length; i++) {
              expect(progress[i], greaterThanOrEqualTo(progress[i - 1]));
            }
            final actual = sha256.convert(await out.readAsBytes()).toString();
            final expected = env['CRISPER_SMB3_BIG_SHA256'];
            if (expected != null) expect(actual, expected);
            final mbps = size / 1048576 / (watch.elapsedMilliseconds / 1000);
            // ignore: avoid_print
            print(
              '[${backend.name}] download ${size ~/ 1048576} MiB in '
              '${watch.elapsedMilliseconds} ms (${mbps.toStringAsFixed(1)} MiB/s)',
            );
          } finally {
            await dir.delete(recursive: true);
          }
        },
        timeout: const Timeout(Duration(minutes: 10)),
        skip: skip,
      );

      test('download refuses a file above its byte limit', () async {
        final s = open(backend);
        final dir = await Directory.systemTemp.createTemp('smb3-q');
        try {
          final out = File('${dir.path}/limited.bin');
          await expectLater(
            s.download(s.urlForPath(big), out, limit: 1024),
            throwsA(anything),
          );
          final written = out.existsSync() ? out.lengthSync() : 0;
          expect(written, lessThanOrEqualTo(1024 * 1024));
        } finally {
          await dir.delete(recursive: true);
        }
      }, skip: skip);

      test(
        'interrupted download completes correctly in a new session',
        () async {
          final dir = await Directory.systemTemp.createTemp('smb3-q');
          try {
            final out = File('${dir.path}/resume.bin');
            final first = open(backend);
            final size = (await first.stat(first.urlForPath(big)))!.size!;
            await expectLater(
              first.download(
                first.urlForPath(big),
                out,
                limit: size,
                onBytes: (n) {
                  if (n > 4 * 1024 * 1024 && n < size) {
                    throw StateError('stop');
                  }
                },
              ),
              throwsA(anything),
            );
            first.close();
            final second = open(backend);
            await second.download(second.urlForPath(big), out, limit: size);
            expect(await out.length(), size);
            final expected = env['CRISPER_SMB3_BIG_SHA256'];
            if (expected != null) {
              expect(
                sha256.convert(await out.readAsBytes()).toString(),
                expected,
              );
            }
          } finally {
            await dir.delete(recursive: true);
          }
        },
        timeout: const Timeout(Duration(minutes: 10)),
        skip: skip,
      );

      test('streams with progress that ends at the file size', () async {
        final s = open(backend);
        final size = (await s.stat(s.urlForPath(chapter)))!.size!;
        final seen = <(int, int)>[];
        var total = 0;
        await for (final c in s.stream(
          s.urlForPath(chapter),
          onProgress: (done, all) => seen.add((done, all)),
        )) {
          total += c.length;
        }
        expect(total, size);
        if (seen.isNotEmpty) {
          expect(seen.last.$1, size);
          expect(seen.every((p) => p.$2 == size || p.$2 <= 0), isTrue);
          for (var i = 1; i < seen.length; i++) {
            expect(seen[i].$1, greaterThanOrEqualTo(seen[i - 1].$1));
          }
        }
      }, skip: skip);

      test('stream of a missing file fails as not found', () async {
        final s = open(backend);
        await expectLater(
          s.stream(s.urlForPath('/missing-$stamp.mp3')).drain<void>(),
          throwsA(isA<RemoteException>()),
        );
      }, skip: skip);

      test(
        'two streams in one session interleave correctly',
        () async {
          final s = open(backend);
          final results = await Future.wait([
            readAll(s, chapter),
            readAll(s, chapter),
          ]);
          expect(results[0].length, results[1].length);
          expect(sha256.convert(results[0]), sha256.convert(results[1]));
        },
        timeout: const Timeout(Duration(minutes: 5)),
        skip: skip,
      );

      test(
        'three sessions read in parallel',
        () async {
          final reference = await readAll(open(backend), chapter);
          final parallel = await Future.wait([
            for (var i = 0; i < 3; i++) readAll(open(backend), chapter),
          ]);
          for (final bytes in parallel) {
            expect(sha256.convert(bytes), sha256.convert(reference));
          }
        },
        timeout: const Timeout(Duration(minutes: 5)),
        skip: skip,
      );

      // --- Writes ---------------------------------------------------------
      test(
        'write then read back small, empty and odd-sized files',
        () async {
          final s = open(backend);
          for (final size in [0, 1, 4095, 4096, 4097, 65537, 262145]) {
            final path = '$scratch/size-$size.bin';
            final data = pattern(size, size);
            await s.write(s.urlForPath(path), data);
            expect((await s.stat(s.urlForPath(path)))!.size, size);
            expect(await readAll(s, path), data, reason: '$size bytes');
          }
        },
        timeout: const Timeout(Duration(minutes: 5)),
        skip: skip,
      );

      test(
        'streamed upload with irregular chunk sizes',
        () async {
          final s = open(backend);
          final data = pattern(3 * 1024 * 1024 + 17, 3);
          final chunks = <List<int>>[];
          for (var i = 0, n = 1; i < data.length; n = n * 7 % 300001 + 1) {
            final end = (i + n).clamp(0, data.length);
            chunks.add(data.sublist(i, end));
            i = end;
          }
          final path = '$scratch/upload.bin';
          await s.upload(s.urlForPath(path), Stream.fromIterable(chunks));
          expect(sha256.convert(await readAll(s, path)), sha256.convert(data));
        },
        timeout: const Timeout(Duration(minutes: 5)),
        skip: skip,
      );

      test('overwrite with shorter content truncates', () async {
        final s = open(backend);
        final path = '$scratch/overwrite.bin';
        await s.write(s.urlForPath(path), pattern(10000));
        await s.write(s.urlForPath(path), pattern(10, 99));
        expect((await s.stat(s.urlForPath(path)))!.size, 10);
        expect(await readAll(s, path), pattern(10, 99));
      }, skip: skip);

      test('failed upload stream does not leave a complete file', () async {
        final s = open(backend);
        final path = '$scratch/aborted.bin';
        Stream<List<int>> failing() async* {
          yield pattern(1000);
          throw StateError('source failed');
        }

        await expectLater(
          s.upload(s.urlForPath(path), failing()),
          throwsA(anything),
        );
        final entry = await s.stat(s.urlForPath(path));
        expect(entry == null || entry.size! <= 1000, isTrue);
      }, skip: skip);

      test('unicode, spaces and reserved URL characters in names', () async {
        final s = open(backend);
        final names = [
          'Hörbuch – Kapitel 1.mp3',
          '第1章 🎧.m4b',
          'a #b %c &d +e ;f =g.mp3',
          "it's (1) [2] {3}.mp3",
        ];
        await s.mkdir(s.urlForPath('$scratch/unicode'));
        for (final (i, name) in names.indexed) {
          await s.write(s.urlForPath('$scratch/unicode/$name'), pattern(64, i));
        }
        final listed = (await s.browse(
          s.urlForPath('$scratch/unicode'),
        )).map((e) => e.name).toSet();
        expect(listed, names.toSet());
        for (final (i, name) in names.indexed) {
          expect(await readAll(s, '$scratch/unicode/$name'), pattern(64, i));
        }
      }, skip: skip);

      // --- Directories ----------------------------------------------------
      test('nested mkdir and browse of each level', () async {
        final s = open(backend);
        await s.mkdir(s.urlForPath('$scratch/n1'));
        await s.mkdir(s.urlForPath('$scratch/n1/n2'));
        await s.mkdir(s.urlForPath('$scratch/n1/n2/n3'));
        await s.write(s.urlForPath('$scratch/n1/n2/n3/leaf.txt'), pattern(5));
        expect((await s.browse(s.urlForPath('$scratch/n1'))).single.name, 'n2');
        final leaf = (await s.browse(s.urlForPath('$scratch/n1/n2/n3'))).single;
        expect((leaf.name, leaf.type, leaf.size), ('leaf.txt', 'file', 5));
      }, skip: skip);

      test(
        'lists a folder with 120 entries completely',
        () async {
          final s = open(backend);
          await s.mkdir(s.urlForPath('$scratch/many'));
          await Future.wait([
            for (var i = 0; i < 120; i++)
              s.write(
                s.urlForPath(
                  '$scratch/many/f${i.toString().padLeft(3, '0')}.bin',
                ),
                pattern(1, i),
              ),
          ]);
          final names = (await s.browse(
            s.urlForPath('$scratch/many'),
          )).map((e) => e.name).toList();
          expect(names.length, 120);
          expect(names.first, 'f000.bin');
          expect(names.last, 'f119.bin');
        },
        timeout: const Timeout(Duration(minutes: 5)),
        skip: skip,
      );

      test('rename a file across folders and rename a folder', () async {
        final s = open(backend);
        await s.mkdir(s.urlForPath('$scratch/from'));
        await s.mkdir(s.urlForPath('$scratch/to'));
        await s.write(s.urlForPath('$scratch/from/a.bin'), pattern(33));
        await s.rename(
          s.urlForPath('$scratch/from/a.bin'),
          s.urlForPath('$scratch/to/b.bin'),
        );
        expect(await s.stat(s.urlForPath('$scratch/from/a.bin')), isNull);
        expect(await readAll(s, '$scratch/to/b.bin'), pattern(33));
        await s.rename(
          s.urlForPath('$scratch/to'),
          s.urlForPath('$scratch/renamed-dir'),
        );
        expect(await s.stat(s.urlForPath('$scratch/to')), isNull);
        expect(await readAll(s, '$scratch/renamed-dir/b.bin'), pattern(33));
      }, skip: skip);

      test('delete refuses non-empty folders and missing files', () async {
        final s = open(backend);
        await s.mkdir(s.urlForPath('$scratch/full'));
        await s.write(s.urlForPath('$scratch/full/x.bin'), pattern(3));
        await expectLater(
          s.delete(s.urlForPath('$scratch/full'), directory: true),
          throwsA(isA<RemoteException>()),
        );
        expect(await s.stat(s.urlForPath('$scratch/full/x.bin')), isNotNull);
        await expectLater(
          s.delete(s.urlForPath('$scratch/nope-$stamp.bin'), directory: false),
          throwsA(isA<RemoteException>()),
        );
      }, skip: skip);

      // --- Confinement ----------------------------------------------------
      test('paths cannot escape the connection root', () async {
        final s = open(backend);
        for (final bad in ['../x', '/a/../../x', r'a\b', 'a/\u0000b']) {
          expect(() => s.urlForPath(bad), throwsFormatException, reason: bad);
        }
      }, skip: skip);

      test('a sub-folder connection only sees its own tree', () async {
        final s = open(backend);
        await s.mkdir(s.urlForPath('$scratch/scope'));
        await s.write(s.urlForPath('$scratch/scope/inside.bin'), pattern(9));
        final scoped = open(
          backend,
          target: '$url${scratch.substring(1)}/scope/',
        );
        final entries = await scoped.browse(scoped.urlForPath('/'));
        expect(entries.map((e) => e.name), ['inside.bin']);
        expect(await readAll(scoped, '/inside.bin'), pattern(9));
        await expectLater(
          scoped.stat(s.urlForPath(big)),
          throwsA(isA<RemoteException>()),
        );
      }, skip: skip);

      // --- Lifecycle ------------------------------------------------------
      test(
        'closing during a download fails it; a new session works',
        () async {
          final s = open(backend);
          final dir = await Directory.systemTemp.createTemp('smb3-q');
          try {
            final out = File('${dir.path}/closed.bin');
            final size = (await s.stat(s.urlForPath(big)))!.size!;
            final running = s.download(s.urlForPath(big), out, limit: size);
            await Future<void>.delayed(const Duration(milliseconds: 300));
            s.close();
            await expectLater(running, throwsA(anything));
            final fresh = open(backend);
            expect(await fresh.stat(fresh.urlForPath(big)), isNotNull);
          } finally {
            await dir.delete(recursive: true);
          }
        },
        timeout: const Timeout(Duration(minutes: 5)),
        skip: skip,
      );

      test('every operation fails as closed after close()', () async {
        final s = open(backend);
        await s.browse(s.urlForPath('/'));
        s.close();
        s.close(); // idempotent
        await expectLater(
          s.browse(s.urlForPath('/')),
          remoteError(RemoteErrorCode.closed),
        );
        await expectLater(
          s.stat(s.urlForPath(big)),
          remoteError(RemoteErrorCode.closed),
        );
        await expectLater(
          s.write(s.urlForPath('$scratch/after-close.bin'), pattern(1)),
          remoteError(RemoteErrorCode.closed),
        );
      }, skip: skip);

      // --- Security and failures -----------------------------------------
      test('rejects a wrong password without falling back', () async {
        final bad = open(backend, secret: 'wrong-password');
        await expectLater(
          bad.browse(bad.urlForPath('/')),
          throwsA(isA<RemoteException>()),
        );
        if (bad.effectiveBackend != null) {
          expect(bad.effectiveBackend, backend);
        }
      }, skip: skip);

      test('rejects an unknown share', () async {
        final s = open(
          backend,
          target: Uri.parse(url!).resolve('/NoSuchShare$stamp/').toString(),
        );
        await expectLater(
          s.browse(s.urlForPath('/')),
          throwsA(isA<RemoteException>()),
        );
      }, skip: skip);

      test(
        'rejects a share the user may not access',
        () async {
          final s = open(backend, target: env['CRISPER_SMB3_DENIED_URL']);
          await expectLater(
            s.browse(s.urlForPath('/')),
            throwsA(isA<RemoteException>()),
          );
        },
        skip: needs('CRISPER_SMB3_DENIED_URL'),
      );

      test(
        'an unreachable server fails promptly',
        () async {
          final s = open(backend, target: 'smb://127.0.0.1:9/Books/');
          await expectLater(
            s.browse(s.urlForPath('/')).timeout(const Duration(seconds: 45)),
            throwsA(isNot(isA<TimeoutException>())),
          );
        },
        timeout: const Timeout(Duration(minutes: 2)),
        skip: skip,
      );

      test(
        'refuses an unencrypted server unless explicitly allowed',
        () async {
          final plain = env['CRISPER_SMB3_PLAIN_URL']!;
          final strict = open(backend, target: plain);
          await expectLater(
            strict.browse(strict.urlForPath('/')),
            throwsA(isA<RemoteException>()),
          );
          final optOut = open(backend, target: plain, encryption: false);
          expect(await optOut.browse(optOut.urlForPath('/')), isA<List>());
        },
        skip: needs('CRISPER_SMB3_PLAIN_URL'),
      );
    });
  }

  // --- Interoperability between the two engines ------------------------
  if (backends.contains(SmbBackend.libsmb2) &&
      backends.contains(SmbBackend.rust)) {
    group('SMB3 libsmb2 ↔ rust', () {
      final scratch = '/q-interop-$stamp';
      tearDownAll(() async {
        if (skip != null) return;
        final s = SmbSession(connection(url!, backend: SmbBackend.libsmb2));
        try {
          await removeTree(s, scratch);
        } finally {
          s.close();
        }
      });

      test(
        'each engine reads what the other wrote',
        () async {
          final lib = open(SmbBackend.libsmb2);
          final rust = open(SmbBackend.rust);
          await rust.mkdir(rust.urlForPath(scratch));
          final a = pattern(700001, 1), b = pattern(500003, 2);
          await rust.write(rust.urlForPath('$scratch/from-rust.bin'), a);
          await lib.write(lib.urlForPath('$scratch/from-libsmb2.bin'), b);
          expect(await readAll(lib, '$scratch/from-rust.bin'), a);
          expect(await readAll(rust, '$scratch/from-libsmb2.bin'), b);
          final libNames = (await lib.browse(
            lib.urlForPath(scratch),
          )).map((e) => (e.name, e.size)).toSet();
          final rustNames = (await rust.browse(
            rust.urlForPath(scratch),
          )).map((e) => (e.name, e.size)).toSet();
          expect(libNames, rustNames);
        },
        timeout: const Timeout(Duration(minutes: 5)),
        skip: skip,
      );

      test('both engines list the share identically', () async {
        final lib = open(SmbBackend.libsmb2);
        final rust = open(SmbBackend.rust);
        String key(RemoteEntry e) => '${e.type}:${e.name}:${e.size}';
        final l = (await lib.browse(lib.urlForPath('/A #1'))).map(key).toList();
        final r = (await rust.browse(
          rust.urlForPath('/A #1'),
        )).map(key).toList();
        expect(r, l);
      }, skip: skip);
    });
  }
}
