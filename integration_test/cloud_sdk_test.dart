import 'dart:io';
import 'dart:typed_data';
import 'package:filen_client/filen_client.dart' as filen;
import 'package:filen_client/aes_gcm_backend.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Filen crypto initializes and authenticates ciphertext in the native sandbox',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'crisper-crypto-native-',
      );
      try {
        final client = filen.FilenClient(
          config: filen.ConfigService(
            configPath: root.path,
            storage: filen.InMemoryConfigStorage(),
          ),
        );
        if (Platform.isMacOS) {
          expect(chooseAesGcmBackend().name, 'cryptography');
        }
        final key = Uint8List.fromList(List.generate(32, (index) => index));
        final original = Uint8List.fromList(
          List.generate(4096, (index) => index % 251),
        );
        final encrypted = await client.crypto.encryptData(original, key);
        expect(await client.crypto.decryptData(encrypted, key), original);
        encrypted[encrypted.length - 1] ^= 1;
        await expectLater(
          client.crypto.decryptData(encrypted, key),
          throwsA(anything),
        );
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}
