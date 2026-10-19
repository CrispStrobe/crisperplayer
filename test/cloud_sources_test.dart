import 'dart:typed_data';
import 'package:crisperplayer/services/server/remote_client.dart';
import 'package:filen_client/filen_client.dart' as filen;
import 'package:internxt_client/internxt_client.dart' as internxt;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Nextcloud builds DAV endpoint with a subdirectory and preserves explicit DAV URL',
    () {
      final c = RemoteConnection(
        id: 'n',
        name: 'Nextcloud',
        kind: 'nextcloud',
        url: 'https://example.com/cloud/',
        username: 'reader@example.com',
        secret: 'app-password',
      );
      expect(
        Uri.decodeComponent(c.url.path),
        '/cloud/remote.php/dav/files/reader@example.com/',
      );
      expect(c.transport.kind, 'webdav');
      expect(RemoteConnection.fromJson(c.toJson(credentials: true)).url, c.url);
      expect(c.toJson().containsKey('secret'), isFalse);
    },
  );
  test(
    'cloud identities use fixed hosts, retain provider and reject escaped paths',
    () {
      for (final kind in ['filen', 'internxt']) {
        final c = RemoteConnection(
          id: kind,
          name: kind,
          kind: kind,
          url: '',
          username: 'reader@example.com',
          secret: '{"token":"fixture"}',
        );
        expect(c.kind, kind);
        expect(c.url.scheme, 'https');
        expect(
          RemoteConnection.fromJson(c.toJson(credentials: true)).kind,
          kind,
        );
        final client = RemoteClient(c);
        for (final path in [
          '../secret',
          '/%2e%2e/secret',
          'https://other.example/file',
          '/a%2fb',
          '/a?token=x',
        ]) {
          expect(() => client.uri(path), throwsFormatException);
        }
        expect(client.uri('/My books/01.mp3').host, c.url.host);
        client.close();
      }
    },
  );
  test(
    'Filen crypto remains compatible with the SSH PointyCastle 4 override',
    () async {
      final crypto = filen.FilenCrypto();
      final metadata = await crypto.encryptMetadata002(
        'Unicode Hörbuch 🎧',
        'fixture-key',
      );
      expect(
        await crypto.decryptMetadata002(metadata, 'fixture-key'),
        'Unicode Hörbuch 🎧',
      );
      final key = Uint8List.fromList(List.generate(32, (i) => i));
      final audio = Uint8List.fromList(List.generate(65537, (i) => i % 256));
      final encrypted = await crypto.encryptData(audio, key);
      expect(await crypto.decryptData(encrypted, key), audio);
      encrypted[encrypted.length - 1] ^= 1;
      await expectLater(crypto.decryptData(encrypted, key), throwsA(anything));
    },
  );
  test('Internxt metadata crypto remains compatible with PointyCastle 4', () {
    final encrypted = internxt.encryptTextWithKey(
      'Hörbuch 🎧',
      'fixture-secret',
    );
    expect(
      internxt.decryptTextWithKey(encrypted, 'fixture-secret'),
      'Hörbuch 🎧',
    );
  });
}
