import 'dart:convert';
import 'dart:typed_data';
import 'package:crisperplayer/services/server/remote_client.dart';
import 'package:filen_client/filen_client.dart' as filen;
import 'package:internxt_client/internxt_client.dart' as internxt;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Internxt renews near-expiry sessions without treating JWT claims as authentication',
    () {
      final now = DateTime.utc(2026, 10, 19);
      String token(int delta) =>
          'header.${base64Url.encode(utf8.encode(jsonEncode({'exp': now.millisecondsSinceEpoch ~/ 1000 + delta}))).replaceAll('=', '')}.signature';
      expect(RemoteClient.internxtSessionNeedsRefresh(token(30), now), isTrue);
      expect(RemoteClient.internxtSessionNeedsRefresh(token(-30), now), isTrue);
      expect(
        RemoteClient.internxtSessionNeedsRefresh(token(3600), now),
        isFalse,
      );
      expect(RemoteClient.internxtSessionNeedsRefresh('invalid', now), isFalse);
    },
  );
  test(
    'Internxt audio and progress listings retain their separately stored extensions',
    () {
      expect(
        RemoteClient.cloudFilename('internxt', {
          'name': 'Track 01',
          'fileType': 'mp3',
        }),
        'Track 01.mp3',
      );
      expect(
        RemoteClient.cloudFilename('internxt', {
          'name': 'crisper-state-device-1',
          'fileType': 'json',
        }),
        'crisper-state-device-1.json',
      );
      expect(
        RemoteClient.cloudFilename('internxt', {
          'name': 'Book.M4B',
          'fileType': 'm4b',
        }),
        'Book.M4B',
      );
      expect(
        RemoteClient.cloudFilename('filen', {'name': 'Book.mp3'}),
        'Book.mp3',
      );
    },
  );
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
