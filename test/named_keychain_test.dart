import 'package:crisperplayer/services/server/credential_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.crispstrobe.crisperplayer/local-keychain');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'named keychain scopes reads, writes and deletes to the explicit path',
    () async {
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'read' ? 'fixture data' : null;
      });
      final store = KeychainCredentialStore(
        key: 'isolated-test',
        macosKeychain: '/selected/brickwright-build.keychain-db',
      );
      expect(await store.read(), 'fixture data');
      await store.write('new fixture data');
      await store.delete();
      expect(calls.map((c) => c.method), ['read', 'write', 'delete']);
      for (final call in calls) {
        expect(
          (call.arguments as Map)['keychain'],
          '/selected/brickwright-build.keychain-db',
        );
        expect((call.arguments as Map)['key'], 'isolated-test');
      }
      expect((calls[1].arguments as Map)['value'], 'new fixture data');
    },
  );

  test(
    'named keychain failures propagate without default-storage fallback',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(
          code: 'named_keychain_-25308',
          message: 'Selected keychain is locked',
        ),
      );
      final store = KeychainCredentialStore(macosKeychain: '/missing/keychain');
      await expectLater(store.read(), throwsA(isA<PlatformException>()));
      await expectLater(
        store.write('fixture'),
        throwsA(isA<PlatformException>()),
      );
      await expectLater(store.delete(), throwsA(isA<PlatformException>()));
    },
  );
}
