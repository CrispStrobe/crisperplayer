import 'package:crisp_storage/crisp_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shared SMB adapter preserves the app default and confined URLs', () {
    final connection = RemoteConnection(
      id: 'fixture',
      name: 'fixture',
      kind: 'smb',
      url: 'smb://localhost/books/audio/',
      username: 'reader',
      secret: 'test-only',
    );
    final session = SmbSession(connection);
    expect(session.backend, SmbBackend.libsmb2);
    expect(session.effectiveBackend, isNull);
    expect(
      session.urlForPath('Chapter #1.mp3'),
      'smb://localhost/books/audio/Chapter%20%231.mp3',
    );
    expect(() => session.urlForPath('../outside'), throwsFormatException);
    session.close();
  });
  test('native qualification is explicit per session', () {
    final connection = RemoteConnection(
      id: 'fixture',
      name: 'fixture',
      kind: 'smb',
      url: 'smb://localhost/books/',
      username: 'reader',
      secret: 'test-only',
    );
    final session = SmbSession(connection, backend: SmbBackend.rust);
    expect(session.backend, SmbBackend.rust);
    expect(connection.requireEncryption, isTrue);
    session.close();
  });
}
