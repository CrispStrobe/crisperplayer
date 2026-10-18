import 'dart:convert';
import 'dart:io';

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
  ]) => _request('/command', body: {'command': name, ...args});

  Future<Object?> importFile(File file) => _request('/import', file: file);

  Future<Object?> _request(
    String path, {
    Map<String, Object?>? body,
    File? file,
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
            : {'name': file.uri.pathSegments.last},
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
