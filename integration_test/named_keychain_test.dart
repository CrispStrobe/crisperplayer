import 'package:crisperplayer/services/server/credential_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const path = String.fromEnvironment('CRISPERPLAYER_MACOS_KEYCHAIN');
  testWidgets(
    'selected keychain stores credentials without searching the default keychain',
    (tester) async {
      expect(
        path,
        isNotEmpty,
        reason:
            'Run with scripts/macos_local.py test --test-file integration_test/named_keychain_test.dart',
      );
      final key =
          'crisperplayer.test.selected.${DateTime.now().microsecondsSinceEpoch}';
      final store = KeychainCredentialStore(key: key);
      try {
        expect(await store.read(), isNull);
        await store.write('isolated native fixture ü');
        expect(await store.read(), 'isolated native fixture ü');
        await store.write('updated fixture');
        expect(await store.read(), 'updated fixture');
        final missing = KeychainCredentialStore(
          key: key,
          macosKeychain: '/tmp/absent-$key.keychain-db',
        );
        await expectLater(missing.read(), throwsA(isA<PlatformException>()));
        await store.delete();
        expect(await store.read(), isNull);
      } finally {
        await store.delete();
      }
    },
    skip: path.isEmpty,
  );
}
