// Live check of `crisperplayer smb-check` (SmbCheck) against a real SMB3
// server. Skipped unless CRISPER_SMB3_URL is set; see the header of
// smb3_backend_qualification_test.dart for the server setup and variables.
import 'dart:io';

import 'package:crisp_storage/crisp_storage.dart';
import 'package:crisperplayer/services/server/smb_check.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final env = Platform.environment;
  final url = env['CRISPER_SMB3_URL'];
  final skip = url == null ? 'Set CRISPER_SMB3_URL for live smb-check.' : null;
  final user = env['CRISPER_SMB3_USER'] ?? 'reader';
  final secret = env['CRISPER_SMB3_SECRET'] ?? 'fixture-password';

  test(
    'both engines pass every step on an encrypted SMB3 share',
    () async {
      final report = await SmbCheck().run(
        url: url!,
        username: user,
        secret: secret,
        engines: const [SmbBackend.libsmb2, SmbBackend.rust],
        file: '/big.bin',
        write: true,
      );
      // ignore: avoid_print
      print(formatSmbCheck(report));
      expect(report['ok'], isTrue);
      for (final engine in (report['engines'] as List).cast<Map>()) {
        expect(engine['effectiveBackend'], engine['engine']);
        final download =
            (engine['steps'] as List).cast<Map>().firstWhere(
                  (s) => s['step'] == 'download',
                )['detail']
                as Map;
        final expected = env['CRISPER_SMB3_BIG_SHA256'];
        if (expected != null) expect(download['sha256'], expected);
        expect(download['mibPerSecond'], isA<double>());
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
    skip: skip,
  );

  test(
    'an unencrypted server fails the connect step for both engines',
    () async {
      final report = await SmbCheck().run(
        url: env['CRISPER_SMB3_PLAIN_URL']!,
        username: user,
        secret: secret,
        write: true,
      );
      expect(report['ok'], isFalse);
      for (final engine in (report['engines'] as List).cast<Map>()) {
        final steps = (engine['steps'] as List).cast<Map>();
        expect(steps.single['step'], 'connect and list');
        expect(steps.single['ok'], isFalse);
      }
    },
    skip:
        skip ??
        (env['CRISPER_SMB3_PLAIN_URL'] == null
            ? 'Set CRISPER_SMB3_PLAIN_URL.'
            : null),
  );
}
