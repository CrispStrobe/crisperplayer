import 'control_protocol.dart';
import 'dart:convert';
import 'dart:io';
import '../utils/folder_import.dart';

/// Pure Dart client: works with `dart run`, without Flutter's runtime.
class ControlClient {
  final File descriptor;
  ControlClient(this.descriptor);

  static File defaultDescriptor() {
    final override = Platform.environment['CRISPERPLAYER_CONTROL_FILE'];
    if (override != null) return File(override);
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    final paths = Platform.isMacOS
        ? [
            '$home/Library/Containers/com.crispstrobe.crisperplayer/Data/Library/Application Support/com.crispstrobe.crisperplayer/cli.json',
            '$home/Library/Application Support/com.crispstrobe.crisperplayer/cli.json',
          ]
        : Platform.isWindows
        ? [
            '${Platform.environment['APPDATA'] ?? home}/com.crispstrobe/crisperplayer/cli.json',
          ]
        : [
            '${Platform.environment['XDG_DATA_HOME'] ?? '$home/.local/share'}/com.crispstrobe.crisperplayer/cli.json',
          ];
    return paths
        .map(File.new)
        .firstWhere(
          (file) => file.existsSync(),
          orElse: () => File(paths.first),
        );
  }

  Future<Object?> command(
    String name, [
    Map<String, Object?> args = const {},
  ]) => _request(
    {'server-cancel', 'server-downloads'}.contains(name)
        ? '/transfers'
        : independentSyncCommands.contains(name)
        ? '/sync'
        : name == 'waveform'
        ? '/waveform'
        : '/command',
    body: {'command': name, ...args},
  );

  Future<Object?> importFile(File file) => _request('/import', file: file);

  Future<Map<String, Object?>> importLibrary(
    String path, {
    bool dryRun = false,
    void Function(int completed, int total, String title)? onProgress,
  }) async {
    final books = await scanBookFolders(path);
    if (books.isEmpty) {
      throw const FormatException('No supported audio files in this folder');
    }
    if (dryRun) {
      return {'books': books.map((book) => book.toJson()).toList()};
    }
    final imported = <Object?>[];
    for (final book in books) {
      onProgress?.call(imported.length, books.length, book.title);
      try {
        final result = await importFiles(
          book.files.map(File.new).toList(),
          title: book.title,
        );
        imported.add({'folder': book.folder, 'result': result});
      } catch (error) {
        // A retry must not silently duplicate books that already succeeded.
        return {
          'complete': false,
          'imported': imported,
          'failedFolder': book.folder,
          'error': '$error',
        };
      }
    }
    return {'complete': true, 'imported': imported};
  }

  Future<Object?> importFiles(
    List<File> files, {
    String? title,
    String? author,
  }) async {
    if (files.isEmpty) throw const FormatException('No audio files supplied');
    if (title == null && files.length > 1) {
      final parts = files.first.parent.uri.pathSegments.where(
        (part) => part.isNotEmpty,
      );
      title = parts.isEmpty ? 'Imported audiobook' : parts.last;
    }
    files = files.toList()..sort((a, b) => naturalPathCompare(a.path, b.path));
    final started = await command('import-begin') as Map;
    final batch = started['batch'] as String;
    try {
      for (final file in files) {
        await _request('/import', file: file, batch: batch);
      }
      return await command('import-commit', {
        'batch': batch,
        'title': ?title,
        'author': ?author,
      });
    } catch (_) {
      try {
        await command('import-cancel', {'batch': batch});
      } catch (_) {
        /* Commit already cleaned up. */
      }
      rethrow;
    }
  }

  Future<Object?> _request(
    String path, {
    Map<String, Object?>? body,
    File? file,
    String? batch,
  }) async {
    if (!await descriptor.exists()) {
      throw StateError(
        'CrisperPlayer is not running with CLI enabled. Start the desktop app first.',
      );
    }
    final config =
        jsonDecode(await descriptor.readAsString()) as Map<String, dynamic>;
    final port = config['port'];
    final token = config['token'];
    if (port is! int || port < 1 || port > 65535 || token is! String) {
      throw const FormatException('Invalid CLI connection file');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    // Loopback requests must never pass through an environment proxy.
    client.findProxy = (_) => 'DIRECT';
    try {
      final uri = Uri(
        scheme: 'http',
        host: '127.0.0.1',
        port: port,
        path: path,
        queryParameters: file == null
            ? null
            : {'name': file.uri.pathSegments.last, 'batch': ?batch},
      );
      final request = await client.postUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      if (file != null) {
        request.headers.contentType = ContentType.binary;
        request.contentLength = await file.length();
        await request.addStream(file.openRead());
      } else {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(
        const Duration(minutes: 10),
      );
      final data = jsonDecode(await utf8.decoder.bind(response).join());
      if (response.statusCode != HttpStatus.ok) {
        throw StateError(
          data is Map
              ? '${data['error']}'
              : 'CLI request failed (${response.statusCode})',
        );
      }
      return data;
    } on SocketException {
      throw StateError(
        'Cannot connect to CrisperPlayer. Restart the desktop app.',
      );
    } finally {
      client.close(force: true);
    }
  }
}
