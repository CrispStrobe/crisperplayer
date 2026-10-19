import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:crisperplayer/services/transfer/browser_upload_server.dart';
import 'package:crisperplayer/services/library_service.dart';
import 'package:crisperplayer/services/db/app_database.dart';
import 'package:drift/native.dart';

void main() {
  late Directory temporary;
  late BrowserUploadServer server;
  late HttpClient client;
  late List<List<String>> imported;
  late List<String?> titles;
  late Uri base;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('upload-test-');
    imported = [];
    titles = [];
    server = BrowserUploadServer(
      temporaryDirectory: () async => temporary,
      maxFileBytes: 128,
      maxBatchBytes: 200,
      importBook: (paths, title) async {
        imported.add([
          for (final path in paths)
            '${p.basename(path)}:${await File(path).readAsString()}',
        ]);
        titles.add(title);
        return 'book-id';
      },
    );
    await server.start(bindAddress: InternetAddress.loopbackIPv4);
    base = Uri.parse(server.addresses.single);
    client = HttpClient();
  });
  tearDown(() async {
    client.close(force: true);
    await server.stop();
    await temporary.delete(recursive: true);
  });

  Future<(int, String)> call(
    String method,
    String path, {
    String? body,
    bool auth = true,
    String? origin,
    String? host,
  }) async {
    final request = await client.openUrl(method, base.resolve(path));
    if (auth) {
      request.headers.set('Authorization', 'Bearer ${server.accessCode}');
    }
    if (origin != null) request.headers.set('Origin', origin);
    if (host != null) request.headers.set('Host', host);
    if (body != null) {
      request.contentLength = utf8.encode(body).length;
      request.write(body);
    }
    final response = await request.close();
    return (response.statusCode, await utf8.decoder.bind(response).join());
  }

  test(
    'streams named tracks, sorts naturally, imports privately and resets batch',
    () async {
      expect(
        (await call('GET', '/', auth: false)).$2,
        contains('Upload audiobooks'),
      );
      expect(
        (await call('PUT', '/upload?name=Chapter%2010.mp3', body: 'ten')).$1,
        200,
      );
      expect(
        (await call('PUT', '/upload?name=Chapter%202.mp3', body: 'two')).$1,
        200,
      );
      expect((await call('POST', '/import?title=My%20book')).$1, 200);
      expect(imported.single, ['Chapter 2.mp3:two', 'Chapter 10.mp3:ten']);
      expect(titles.single, 'My book');
      expect((await call('POST', '/import')).$1, 400);
      expect((await call('GET', '/library')).$1, 404);
      await server.stop();
      expect(await temporary.list().toList(), isEmpty);
    },
  );

  test(
    'rejects missing credentials, cross-origin requests and hostile Host',
    () async {
      expect(
        (await call('PUT', '/upload?name=a.mp3', body: 'a', auth: false)).$1,
        401,
      );
      expect(
        (await call('POST', '/import', origin: 'https://evil.example')).$1,
        403,
      );
      expect((await call('GET', '/', host: 'evil.example')).$1, 403);
      expect(imported, isEmpty);
    },
  );

  test(
    'rejects traversal, nonaudio and oversized uploads without importing',
    () async {
      for (final name in [
        '../a.mp3',
        '..\\a.mp3',
        '/a.mp3',
        'a.txt',
        'C:relative.mp3',
        'wild*.mp3',
        'a\u0000.mp3',
      ]) {
        expect(
          (await call(
            'PUT',
            '/upload?name=${Uri.encodeQueryComponent(name)}',
            body: 'a',
          )).$1,
          400,
        );
      }
      expect(
        (await call('PUT', '/upload?name=a.mp3', body: 'a' * 129)).$1,
        413,
      );
      expect(
        (await call('PUT', '/upload?name=a.mp3', body: 'a' * 110)).$1,
        200,
      );
      expect(
        (await call('PUT', '/upload?name=b.mp3', body: 'b' * 110)).$1,
        413,
      );
      expect(imported, isEmpty);
    },
  );

  test('retry replaces same file without counting twice', () async {
    expect((await call('PUT', '/upload?name=a.mp3', body: 'old')).$1, 200);
    expect((await call('PUT', '/upload?name=a.mp3', body: 'new')).$1, 200);
    expect((await call('POST', '/import')).$1, 200);
    expect(imported.single, ['a.mp3:new']);
  });

  test('stop during startup leaves no listener or staging directory', () async {
    await server.stop();
    final gate = Completer<Directory>();
    final starting = BrowserUploadServer(
      importBook: (_, _) async => null,
      temporaryDirectory: () => gate.future,
    );
    final future = starting.start(bindAddress: InternetAddress.loopbackIPv4);
    final failed = expectLater(future, throwsStateError);
    final stopping = starting.stop();
    gate.complete(temporary);
    await failed;
    await stopping;
    expect(starting.port, 0);
    expect(await temporary.list().toList(), isEmpty);
  });

  test(
    'stopping an interrupted upload promptly removes its partial file',
    () async {
      final socket = await Socket.connect('127.0.0.1', server.port);
      socket.listen((_) {}, onError: (_) {});
      socket.write(
        'PUT /upload?name=partial.mp3 HTTP/1.1\r\n'
        'Host: 127.0.0.1:${server.port}\r\n'
        'Authorization: Bearer ${server.accessCode}\r\n'
        'Content-Length: 100\r\n\r\nshort',
      );
      await socket.flush();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      try {
        await server.stop().timeout(const Duration(seconds: 3));
        expect(await temporary.list().toList(), isEmpty);
        expect(imported, isEmpty);
      } finally {
        socket.destroy();
      }
    },
  );

  test('serializes imports and stop waits for a library commit', () async {
    await server.stop();
    final entered = Completer<void>();
    final release = Completer<void>();
    server = BrowserUploadServer(
      temporaryDirectory: () async => temporary,
      importBook: (_, _) async {
        entered.complete();
        await release.future;
        return 'committed';
      },
    );
    await server.start(bindAddress: InternetAddress.loopbackIPv4);
    base = Uri.parse(server.addresses.single);
    expect((await call('PUT', '/upload?name=one.mp3', body: 'audio')).$1, 200);
    final importing = call('POST', '/import');
    await entered.future;
    try {
      expect(
        (await call('PUT', '/upload?name=two.mp3', body: 'audio')).$1,
        409,
      );
      var stopped = false;
      final stopping = server.stop().then((_) => stopped = true);
      final disconnected = importing.then<void>((_) {}, onError: (Object _) {});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(stopped, isFalse);
      release.complete();
      await stopping;
      await disconnected;
      expect(await temporary.list().toList(), isEmpty);
    } finally {
      if (!release.isCompleted) release.complete();
    }
  });

  test(
    'real library import owns uploaded audio after inbox is stopped',
    () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final library = LibraryService(
        db,
        storageDirectory: () async => temporary,
        probeDuration: (_) async => const Duration(seconds: 1),
      );
      final real = BrowserUploadServer(
        temporaryDirectory: () async => temporary,
        importBook: (paths, title) =>
            library.importFiles(paths, title: title, preserveOrder: true),
      );
      await real.start(bindAddress: InternetAddress.loopbackIPv4);
      final previous = server;
      server = real;
      base = Uri.parse(real.addresses.single);
      try {
        // Metadata parser tolerates unknown headers; playback probing is injected.
        expect(
          (await call(
            'PUT',
            '/upload?name=track.mp3',
            body: 'audio fixture',
          )).$1,
          200,
        );
        expect((await call('POST', '/import?title=Uploaded')).$1, 200);
        await real.stop();
        final book = (await library.allBooks()).single;
        expect(book.title, 'Uploaded');
        final paths = AppDatabase.decodePaths(book.filePathsJson);
        expect(await File(paths.single).readAsString(), 'audio fixture');
      } finally {
        await previous.stop();
        await db.close();
      }
    },
  );
}
