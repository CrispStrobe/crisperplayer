// Live SMB3 qualification of both SMB backends against a real server.
//
// Skipped unless CRISPER_SMB3_URL is set, e.g.
//   CRISPER_SMB3_URL=smb://127.0.0.1:1445/Books/
//   CRISPER_SMB3_USER=reader CRISPER_SMB3_SECRET=fixture-password
//   CRISPER_SMB3_BIG_SHA256=<sha256 of big.bin>          (optional)
//   CRISPER_SMB3_PLAIN_URL=smb://127.0.0.1:1446/Books/   (optional server
//     WITHOUT encryption, to prove that required encryption is refused)
//   CRISP_SMB_LIBRARY=/abs/path/libcrisp_smb_bridge.dylib (Rust backend)
//
// On iOS run integration_test/smb3_backend_qualification_test.dart with the
// same names as --dart-define values (CRISP_SMB_LIBRARY included).
//   CRISPER_SMB3_BACKENDS=libsmb2,rust                   (default: both)
//
// The server should require SMB3, signing and encryption. The share must
// contain `big.bin` and `A #1/Chapter 1.mp3`; scratch files are created and
// removed under `/qualification-<backend>/`.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_storage/crisp_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // --dart-define wins (needed on iOS simulators/devices, which do not see the
  // host environment); otherwise fall back to process environment variables.
  const defines = {
    'CRISPER_SMB3_URL': String.fromEnvironment('CRISPER_SMB3_URL'),
    'CRISPER_SMB3_USER': String.fromEnvironment('CRISPER_SMB3_USER'),
    'CRISPER_SMB3_SECRET': String.fromEnvironment('CRISPER_SMB3_SECRET'),
    'CRISPER_SMB3_BIG_SHA256': String.fromEnvironment(
      'CRISPER_SMB3_BIG_SHA256',
    ),
    'CRISPER_SMB3_PLAIN_URL': String.fromEnvironment('CRISPER_SMB3_PLAIN_URL'),
    'CRISPER_SMB3_BACKENDS': String.fromEnvironment('CRISPER_SMB3_BACKENDS'),
  };
  final env = {
    ...Platform.environment,
    for (final e in defines.entries)
      if (e.value.isNotEmpty) e.key: e.value,
  };
  final url = env['CRISPER_SMB3_URL'];
  final skip = url == null
      ? 'Set CRISPER_SMB3_URL to run live SMB3 checks.'
      : null;
  final backends = (env['CRISPER_SMB3_BACKENDS'] ?? 'libsmb2,rust')
      .split(',')
      .map((b) => parseSmbBackend(b.trim())!)
      .toList();

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

  for (final backend in backends) {
    group('SMB3 ${backend.name}', () {
      late SmbSession session;
      final scratch = '/qualification-${backend.name}';

      setUp(() => session = SmbSession(connection(url!, backend: backend)));
      tearDown(() => session.close());

      test('selects the requested backend and browses the share', () async {
        final entries = await session.browse(session.urlForPath('/'));
        expect(session.effectiveBackend, backend);
        final names = entries.map((e) => e.name).toSet();
        expect(names, containsAll(['big.bin', 'A #1']));
        final big = await session.stat(session.urlForPath('/big.bin'));
        expect(big, isNotNull);
        expect(big!.size, greaterThan(0));
      }, skip: skip);

      test(
        'downloads a large file byte-exactly',
        () async {
          final dir = await Directory.systemTemp.createTemp('smb3-q');
          try {
            final out = File('${dir.path}/big.bin');
            final size = (await session.stat(
              session.urlForPath('/big.bin'),
            ))!.size!;
            var reported = 0;
            final watch = Stopwatch()..start();
            await session.download(
              session.urlForPath('/big.bin'),
              out,
              onBytes: (n) => reported = n,
              limit: size,
            );
            watch.stop();
            expect(await out.length(), size);
            expect(reported, size);
            final expected = env['CRISPER_SMB3_BIG_SHA256'];
            final actual = sha256.convert(await out.readAsBytes()).toString();
            if (expected != null) expect(actual, expected);
            final mbps = size / 1048576 / (watch.elapsedMilliseconds / 1000);
            // ignore: avoid_print
            print(
              '[${backend.name}] download ${size ~/ 1048576} MiB in '
              '${watch.elapsedMilliseconds} ms (${mbps.toStringAsFixed(1)} MiB/s)'
              ' sha256=$actual',
            );
          } finally {
            await dir.delete(recursive: true);
          }
        },
        timeout: const Timeout(Duration(minutes: 10)),
        skip: skip,
      );

      test(
        'streams a path with spaces and # exactly',
        () async {
          final path = '/A #1/Chapter 1.mp3';
          final size = (await session.stat(session.urlForPath(path)))!.size!;
          final builder = BytesBuilder(copy: false);
          await for (final chunk in session.stream(session.urlForPath(path))) {
            builder.add(chunk);
          }
          expect(builder.length, size);
          // ignore: avoid_print
          print(
            '[${backend.name}] stream sha256='
            '${sha256.convert(builder.takeBytes())}',
          );
        },
        timeout: const Timeout(Duration(minutes: 5)),
        skip: skip,
      );

      test(
        'write, upload, rename, browse and delete round trip',
        () async {
          if (await session.stat(session.urlForPath(scratch)) != null) {
            for (final e in await session.browse(session.urlForPath(scratch))) {
              await session.delete(
                session.urlForPath('$scratch/${e.name}'),
                directory: false,
              );
            }
            await session.delete(session.urlForPath(scratch), directory: true);
          }
          await session.mkdir(session.urlForPath(scratch));
          final small = Uint8List.fromList(List.generate(4096, (i) => i % 251));
          await session.write(session.urlForPath('$scratch/small.bin'), small);
          final payload = Uint8List.fromList(
            List.generate(3 * 1024 * 1024 + 17, (i) => (i * 31) % 256),
          );
          await session.upload(
            session.urlForPath('$scratch/upload.bin'),
            Stream.fromIterable([
              for (var i = 0; i < payload.length; i += 65536)
                payload.sublist(
                  i,
                  i + 65536 > payload.length ? payload.length : i + 65536,
                ),
            ]),
          );
          await session.rename(
            session.urlForPath('$scratch/upload.bin'),
            session.urlForPath('$scratch/renamed.bin'),
          );
          final names = (await session.browse(
            session.urlForPath(scratch),
          )).map((e) => e.name).toSet();
          expect(names, {'small.bin', 'renamed.bin'});
          final back = BytesBuilder(copy: false);
          await for (final c in session.stream(
            session.urlForPath('$scratch/renamed.bin'),
          )) {
            back.add(c);
          }
          expect(sha256.convert(back.takeBytes()), sha256.convert(payload));
          final smallBack = BytesBuilder(copy: false);
          await for (final c in session.stream(
            session.urlForPath('$scratch/small.bin'),
          )) {
            smallBack.add(c);
          }
          expect(smallBack.takeBytes(), small);
          await session.delete(
            session.urlForPath('$scratch/small.bin'),
            directory: false,
          );
          await session.delete(
            session.urlForPath('$scratch/renamed.bin'),
            directory: false,
          );
          await session.delete(session.urlForPath(scratch), directory: true);
          expect(await session.stat(session.urlForPath(scratch)), isNull);
        },
        timeout: const Timeout(Duration(minutes: 5)),
        skip: skip,
      );

      test('rejects a wrong password without falling back', () async {
        final bad = SmbSession(
          connection(url!, secret: 'wrong-password', backend: backend),
        );
        try {
          await expectLater(
            bad.browse(bad.urlForPath('/')),
            throwsA(isA<RemoteException>()),
          );
          if (bad.effectiveBackend != null) {
            expect(bad.effectiveBackend, backend);
          }
        } finally {
          bad.close();
        }
      }, skip: skip);

      test(
        'refuses a server without encryption when it is required',
        () async {
          final plain = env['CRISPER_SMB3_PLAIN_URL']!;
          final s = SmbSession(connection(plain, backend: backend));
          try {
            await expectLater(
              s.browse(s.urlForPath('/')),
              throwsA(isA<RemoteException>()),
            );
          } finally {
            s.close();
          }
          // The explicit opt-out still connects (signed, unencrypted).
          final optOut = SmbSession(
            connection(plain, encryption: false, backend: backend),
          );
          try {
            expect(
              await optOut.browse(optOut.urlForPath('/')),
              isA<List<RemoteEntry>>(),
            );
          } finally {
            optOut.close();
          }
        },
        skip:
            skip ??
            (env['CRISPER_SMB3_PLAIN_URL'] == null
                ? 'Set CRISPER_SMB3_PLAIN_URL for the encryption refusal check.'
                : null),
      );
    });
  }
}
