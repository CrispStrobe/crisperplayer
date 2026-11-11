import 'dart:convert';
import 'dart:io';

import 'package:crisperplayer/cli/control_client.dart';
import 'package:crisperplayer/services/desktop_control_service.dart';
import 'package:crisperplayer/services/server/credential_store.dart';
import 'package:crisperplayer/services/server/remote_client.dart';
import 'package:crisperplayer/services/server/remote_library_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playback_harness.dart';

class _Credentials implements ServerCredentialStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async => value = next;
  @override
  Future<void> delete() async => value = null;
}

class _Remote extends RemoteLibraryService {
  _Remote(super.library, {required super.credentials});
  bool transferBusy = false;
  @override
  bool get busy => transferBusy || super.busy;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test(
    'GUI service and CLI share backend persistence without exporting secrets',
    () async {
      final h = PlaybackHarness();
      await h.init();
      final store = _Credentials()
        ..value = jsonEncode([
          RemoteConnection(
            id: 'nas',
            name: 'NAS',
            kind: 'smb',
            url: 'smb://nas/books',
            username: 'reader',
            secret: 'smb-password',
          ).toJson(credentials: true),
        ]);
      final remote = _Remote(h.library, credentials: store);
      final control = DesktopControlService(
        library: h.library,
        playback: h.playback,
        remote: remote,
        descriptor: File('${h.root.path}/smb-cli.json'),
      );
      try {
        await remote.init();
        // Profiles saved before the choice existed use the app default.
        expect(remote.connections.single.smbBackend, appDefaultSmbBackend);
        expect(appDefaultSmbBackend, SmbBackend.auto);
        await control.start();
        final cli = ControlClient(control.descriptor);
        for (final backend in SmbBackend.values) {
          // The settings screen calls this exact service method.
          await remote.setSmbBackend('nas', backend);
          final read =
              await cli.command('server-settings', {'connectionId': 'nas'})
                  as Map;
          expect(read['smbBackend'], backend.name);
          expect(jsonEncode(read), isNot(contains('smb-password')));
          expect(read.containsKey('secret'), isFalse);
          final selected =
              SmbBackend.values[(backend.index + 1) % SmbBackend.values.length];
          final result =
              await cli.command('server-settings', {
                    'connectionId': 'nas',
                    'smbBackend': selected.name,
                  })
                  as Map;
          expect(result['smbBackend'], selected.name);
          expect(remote.connections.single.smbBackend, selected);
          expect(remote.connections.single.secret, 'smb-password');
          final restored = RemoteLibraryService(h.library, credentials: store);
          try {
            await restored.init();
            expect(restored.connections.single.smbBackend, selected);
            expect(restored.connections.single.requireEncryption, isTrue);
          } finally {
            restored.dispose();
          }
        }
        final before = store.value;
        for (final invalid in ['unknown', null, 7]) {
          await expectLater(
            cli.command('server-settings', {
              'connectionId': 'nas',
              'smbBackend': invalid,
            }),
            throwsA(isA<Object>()),
          );
          expect(store.value, before);
        }
        remote.transferBusy = true;
        await expectLater(
          remote.setSmbBackend('nas', SmbBackend.libsmb2),
          throwsA(isA<RemoteException>()),
        );
        expect(store.value, before);
        remote.transferBusy = false;
        await expectLater(
          remote.setSmbBackend('missing', SmbBackend.rust),
          throwsFormatException,
        );
        expect(store.value, before);
      } finally {
        await control.dispose();
        remote.dispose();
        await h.dispose();
      }
    },
  );
}
