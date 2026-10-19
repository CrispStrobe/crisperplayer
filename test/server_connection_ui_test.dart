import 'package:crisperplayer/providers/providers.dart';
import 'package:crisperplayer/screens/sync_settings_screen.dart';
import 'package:crisperplayer/services/db/app_database.dart';
import 'package:crisperplayer/services/library_service.dart';
import 'package:crisperplayer/services/server/remote_client.dart';
import 'package:crisperplayer/services/server/remote_library_service.dart';
import 'package:crisperplayer/services/server/sftp_reader.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'remote_library_test.dart' show MemoryCredentials;

class HostKeyProbe extends RemoteLibraryService {
  static final pin = 'SHA256:${List.filled(43, 'A').join()}';
  int attempts = 0;
  RemoteConnection? connected;
  HostKeyProbe(super.library) : super(credentials: MemoryCredentials());
  @override
  Future<void> init() async {}
  @override
  List<RemoteConnection> get connections => [?connected];
  @override
  Future<void> connect({
    required String name,
    required String kind,
    required String url,
    required String secret,
    String username = '',
    bool allowLocalHttp = false,
    bool requireEncryption = true,
    String? hostKey,
    String? twoFactorCode,
  }) async {
    attempts++;
    if (hostKey != pin) throw SftpHostKeyException(pin);
    connected = RemoteConnection(
      id: 'fixture',
      name: name,
      kind: kind,
      url: url,
      secret: secret,
      username: username,
      hostKey: hostKey,
    );
    notifyListeners();
  }
}

class SmbProbe extends RemoteLibraryService {
  RemoteConnection? connected;
  SmbProbe(super.library) : super(credentials: MemoryCredentials());
  @override
  Future<void> init() async {}
  @override
  List<RemoteConnection> get connections => [?connected];
  @override
  Future<void> connect({
    required String name,
    required String kind,
    required String url,
    required String secret,
    String username = '',
    bool allowLocalHttp = false,
    bool requireEncryption = true,
    String? hostKey,
    String? twoFactorCode,
  }) async {
    connected = RemoteConnection(
      id: 'smb-fixture',
      name: name,
      kind: kind,
      url: url,
      username: username,
      secret: secret,
      requireEncryption: requireEncryption,
    );
    notifyListeners();
  }
}

void main() {
  testWidgets(
    'SMB dialog requires encryption by default and passes an explicit SMB2 choice',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final remote = SmbProbe(LibraryService(db));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [remoteLibraryProvider.overrideWith((ref) => remote)],
          child: const MaterialApp(home: SyncSettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add server'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SMB / NAS').last);
      await tester.pumpAndSettle();
      expect(find.text('Allow HTTP on the local network'), findsNothing);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue,
      );
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'My NAS');
      await tester.enterText(fields.at(1), 'smb://nas.local/Audio%20Books/');
      await tester.enterText(fields.at(2), r'HOME\reader');
      await tester.enterText(fields.at(3), 'fixture-password');
      await tester.ensureVisible(find.text('Require SMB3 encryption'));
      await tester.tap(find.text('Require SMB3 encryption'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(remote.connected!.kind, 'smb');
      expect(remote.connected!.requireEncryption, isFalse);
      expect(remote.connected!.username, r'HOME\reader');
      await tester.pumpWidget(const SizedBox.shrink());
      await db.close();
    },
  );
  testWidgets(
    'SFTP dialog requires explicit trust, and changing the address clears the offered key',
    (tester) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final remote = HostKeyProbe(LibraryService(db));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [remoteLibraryProvider.overrideWith((ref) => remote)],
          child: const MaterialApp(home: SyncSettingsScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Add server'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SFTP / NAS').last);
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'My NAS');
      await tester.enterText(fields.at(1), 'sftp://nas.local/books/');
      await tester.enterText(fields.at(2), 'reader');
      await tester.enterText(fields.at(3), 'fixture-password');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(remote.attempts, 1);
      expect(find.text('Trust this server key'), findsOneWidget);
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(remote.attempts, 1);
      expect(remote.connected, isNull);
      await tester.enterText(fields.at(1), 'sftp://other-nas.local/books/');
      await tester.pumpAndSettle();
      expect(find.text('Trust this server key'), findsNothing);
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(remote.attempts, 2);
      await tester.ensureVisible(find.text('Trust this server key'));
      await tester.tap(find.text('Trust this server key'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();
      expect(remote.attempts, 3);
      expect(remote.connected!.hostKey, HostKeyProbe.pin);
      expect(remote.connected!.url.host, 'other-nas.local');
      expect(find.text('My NAS'), findsOneWidget);
      expect(find.text('Add server'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await db.close();
    },
  );
}
