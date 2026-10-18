import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:xml/xml.dart';

class RemoteException implements Exception {
  final String message;
  const RemoteException(this.message);
  @override
  String toString() => message;
}

class RemoteConnection {
  final String id, name, kind, username, secret;
  final Uri url;
  final bool allowLocalHttp;
  RemoteConnection({
    required this.id,
    required this.name,
    required this.kind,
    required String url,
    this.username = '',
    required this.secret,
    this.allowLocalHttp = false,
  }) : url = validateUrl(url, allowLocalHttp) {
    if (!{'plex', 'webdav'}.contains(kind) ||
        name.trim().isEmpty ||
        secret.isEmpty ||
        name.length > 200 ||
        username.contains(':') ||
        secret.contains('\r') ||
        secret.contains('\n')) {
      throw const FormatException(
        'Enter a connection name and valid credentials.',
      );
    }
  }
  static Uri validateUrl(String text, bool localHttp) {
    final uri = Uri.tryParse(text.trim());
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.scheme != 'https' &&
            !(uri.scheme == 'http' && localHttp && isLocalHost(uri.host)))) {
      throw const FormatException(
        'Use an HTTPS server URL. For a local server, enable local HTTP explicitly.',
      );
    }
    final result = uri.replace(
      path: '${uri.path.replaceFirst(RegExp(r'/+$'), '')}/',
    );
    _safePath(result);
    return result;
  }

  static bool isLocalHost(String host) {
    if (host == 'localhost' || host.endsWith('.local')) return true;
    final address = InternetAddress.tryParse(host);
    if (address == null) return false;
    if (address.isLoopback || address.isLinkLocal) return true;
    final bytes = address.rawAddress;
    if (bytes.length == 4) {
      return bytes[0] == 10 ||
          (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
          (bytes[0] == 192 && bytes[1] == 168);
    }
    return (bytes[0] & 0xfe) == 0xfc;
  }

  static void _safePath(Uri uri) {
    final decoded = Uri.decodeComponent(uri.path);
    if (decoded.contains('\\') ||
        decoded.split('/').any((s) => s == '..' || s == '.')) {
      throw const FormatException('Invalid server path.');
    }
  }

  Map<String, Object?> toJson({bool credentials = false}) => {
    'id': id,
    'name': name,
    'kind': kind,
    'url': url.toString(),
    'username': username,
    'allowLocalHttp': allowLocalHttp,
    if (credentials) 'secret': secret,
  };
  factory RemoteConnection.fromJson(Map<String, dynamic> json) =>
      RemoteConnection(
        id: json['id'] as String,
        name: json['name'] as String,
        kind: json['kind'] as String,
        url: json['url'] as String,
        username: json['username'] as String? ?? '',
        secret: json['secret'] as String,
        allowLocalHttp: json['allowLocalHttp'] == true,
      );
}

class RemoteEntry {
  final String path, name, type, author;
  final int? size;
  const RemoteEntry(
    this.path,
    this.name,
    this.type, {
    this.author = '',
    this.size,
  });
  Map<String, Object?> toJson() => {
    'path': path,
    'name': name,
    'type': type,
    'author': author,
    'size': size,
  };
}

/// Read-only Plex and WebDAV transport. Credentials never enter media URLs.
class RemoteClient {
  final RemoteConnection connection;
  final HttpClient _http;
  RemoteClient(this.connection, {HttpClient? httpClient})
    : _http = httpClient ?? HttpClient() {
    _http.connectionTimeout = const Duration(seconds: 10);
    _http.idleTimeout = const Duration(seconds: 15);
  }
  Uri uri(String path) {
    final base = connection.url;
    final reference = Uri.parse(path);
    RemoteConnection._safePath(reference);
    final result = base.resolve(path);
    if (result.scheme != base.scheme ||
        result.host != base.host ||
        result.port != base.port ||
        !result.path.startsWith(base.path) ||
        result.userInfo.isNotEmpty ||
        result.hasFragment ||
        result.queryParameters.keys.any(
          (k) =>
              {'x-plex-token', 'token', 'password'}.contains(k.toLowerCase()),
        )) {
      throw const RemoteException(
        'The server returned a URL outside this connection.',
      );
    }
    RemoteConnection._safePath(result);
    return result;
  }

  Future<HttpClientResponse> _request(
    String path, {
    bool listing = false,
  }) async {
    try {
      final request = await _http
          .openUrl(
            listing && connection.kind == 'webdav' ? 'PROPFIND' : 'GET',
            uri(path),
          )
          .timeout(const Duration(seconds: 15));
      request.followRedirects = false;
      if (connection.kind == 'plex') {
        request.headers.set('X-Plex-Token', connection.secret);
        request.headers.set('X-Plex-Product', 'CrisperPlayer');
        request.headers.set(
          'X-Plex-Client-Identifier',
          'crisperplayer-${connection.id}',
        );
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      } else {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Basic ${base64Encode(utf8.encode('${connection.username}:${connection.secret}'))}',
        );
        if (listing) {
          request.headers.set('Depth', '1');
          request.headers.contentType = ContentType(
            'application',
            'xml',
            charset: 'utf-8',
          );
          request.write(
            '<?xml version="1.0"?><propfind xmlns="DAV:"><prop><displayname/><resourcetype/><getcontentlength/></prop></propfind>',
          );
        }
      }
      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final status = response.statusCode;
        await response.drain<void>().timeout(const Duration(seconds: 5));
        throw RemoteException(switch (status) {
          401 || 403 => 'Access denied. Check the connection credentials.',
          >= 300 && < 400 =>
            'Use the final server URL; redirects are not followed.',
          _ => 'Server request failed (HTTP $status).',
        });
      }
      return response;
    } on RemoteException {
      rethrow;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const RemoteException(
        'Could not reach the server. Check its address and network access.',
      );
    }
  }

  Future<String> _text(String path, {bool listing = false}) async {
    final response = await _request(path, listing: listing);
    final data = BytesBuilder(copy: false);
    await for (final bytes in response.timeout(const Duration(seconds: 20))) {
      data.add(bytes);
      if (data.length > 16 * 1024 * 1024) {
        throw const RemoteException('Server listing is too large.');
      }
    }
    return utf8.decode(data.takeBytes());
  }

  Future<List<Map<String, dynamic>>> _plexRows(String path, String key) async {
    final rows = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      final target = uri(path);
      final paged = target.replace(
        queryParameters: {
          ...target.queryParameters,
          'X-Plex-Container-Start': '$offset',
          'X-Plex-Container-Size': '200',
        },
      );
      final root =
          (jsonDecode(await _text(paged.toString())) as Map)['MediaContainer']
              as Map;
      final page = (root[key] as List? ?? []).cast<Map>();
      rows.addAll(page.map((r) => r.cast<String, dynamic>()));
      final total = (root['totalSize'] as num?)?.toInt();
      if (total == null || page.isEmpty || rows.length >= total) break;
      offset += page.length;
      if (rows.length >= 10000) {
        throw const RemoteException(
          'Library is too large. Open a smaller library.',
        );
      }
    }
    return rows;
  }

  Future<List<RemoteEntry>> browse(String path) async {
    if (connection.kind == 'plex') {
      if (path.isEmpty) {
        final rows = await _plexRows('library/sections', 'Directory');
        return [
          for (final r in rows)
            if (r['type'] == 'artist')
              RemoteEntry(
                'library/sections/${Uri.encodeComponent('${r['key']}')}/all?type=9',
                '${r['title']}',
                'folder',
              ),
        ];
      }
      final rows = await _plexRows(path, 'Metadata');
      return [
        for (final r in rows)
          if (r['type'] == 'album')
            RemoteEntry(
              'library/metadata/${Uri.encodeComponent('${r['ratingKey']}')}/children',
              '${r['title']}',
              'book',
              author: r['parentTitle'] as String? ?? '',
            ),
      ];
    }
    final target = path.isEmpty ? connection.url.toString() : path;
    final document = XmlDocument.parse(await _text(target, listing: true));
    final entries = <RemoteEntry>[];
    for (final response in document.descendants.whereType<XmlElement>().where(
      (e) => e.name.local == 'response',
    )) {
      final href = response.childElements
          .where((e) => e.name.local == 'href')
          .firstOrNull
          ?.innerText;
      if (href == null) continue;
      final resolved = uri(href);
      if (resolved.path.replaceFirst(RegExp(r'/+$'), '') ==
          uri(target).path.replaceFirst(RegExp(r'/+$'), '')) {
        continue;
      }
      final props = response.childElements
          .where((e) => e.name.local == 'propstat')
          .where(
            (p) => p.childElements.any(
              (e) =>
                  e.name.local == 'status' &&
                  RegExp(r'\s200\s').hasMatch(e.innerText),
            ),
          )
          .expand((p) => p.childElements.where((e) => e.name.local == 'prop'))
          .expand((p) => p.childElements)
          .toList();
      if (props.isEmpty) continue;
      final folder = props.any(
        (e) =>
            e.name.local == 'resourcetype' &&
            e.childElements.any((e) => e.name.local == 'collection'),
      );
      final name = props
          .where((e) => e.name.local == 'displayname')
          .firstOrNull
          ?.innerText;
      entries.add(
        RemoteEntry(
          resolved.toString(),
          name?.isNotEmpty == true
              ? name!
              : Uri.decodeComponent(
                  resolved.path.split('/').where((s) => s.isNotEmpty).last,
                ),
          folder ? 'folder' : 'file',
          size: int.tryParse(
            props
                    .where((e) => e.name.local == 'getcontentlength')
                    .firstOrNull
                    ?.innerText ??
                '',
          ),
        ),
      );
    }
    entries.sort(
      (a, b) => a.type == b.type
          ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
          : a.type == 'folder'
          ? -1
          : 1,
    );
    return entries;
  }

  Future<List<RemoteEntry>> tracks(String path) async {
    if (connection.kind != 'plex') {
      return (await browse(
        path,
      )).where((e) => e.type == 'file' && isAudio(e.name)).toList();
    }
    final rows = await _plexRows(path, 'Metadata');
    rows.sort((a, b) {
      final disc = ((a['parentIndex'] as num?)?.toInt() ?? 1).compareTo(
        (b['parentIndex'] as num?)?.toInt() ?? 1,
      );
      return disc != 0
          ? disc
          : ((a['index'] as num?)?.toInt() ?? 0).compareTo(
              (b['index'] as num?)?.toInt() ?? 0,
            );
    });
    final result = <RemoteEntry>[];
    for (final r in rows) {
      if (r['type'] != 'track') continue;
      final media = (r['Media'] as List? ?? []).whereType<Map>().firstOrNull;
      for (final part in (media?['Part'] as List? ?? []).whereType<Map>()) {
        final key = part['key'];
        if (key is! String) continue;
        final filename = (part['file'] as String? ?? '')
            .split(RegExp(r'[/\\]'))
            .last;
        final container =
            '${part['container'] ?? media?['container'] ?? 'mp3'}';
        result.add(
          RemoteEntry(
            key,
            isAudio(filename) ? filename : '${r['title']}.$container',
            'file',
            size: (part['size'] as num?)?.toInt(),
          ),
        );
      }
    }
    return result;
  }

  static bool isAudio(String name) => {
    'm4b',
    'm4a',
    'mp3',
    'flac',
    'ogg',
    'wav',
    'aac',
    'opus',
    'wma',
    'aiff',
    'aif',
    'mp2',
    'mov',
    'webm',
    '3gp',
    'mkv',
    'mka',
  }.contains(name.split('.').last.toLowerCase());
  Future<void> download(
    String path,
    File output, {
    void Function(int)? onBytes,
    int limit = 64 * 1024 * 1024 * 1024,
  }) async {
    final response = await _request(path);
    if (response.contentLength > limit) {
      throw const RemoteException('File exceeds the download limit.');
    }
    final sink = output.openWrite();
    var received = 0;
    try {
      await for (final bytes in response.timeout(const Duration(seconds: 30))) {
        received += bytes.length;
        if (received > limit) {
          throw const RemoteException('File exceeds the download limit.');
        }
        sink.add(bytes);
        if (received % (1024 * 1024) < bytes.length) await sink.flush();
        onBytes?.call(received);
      }
      await sink.flush();
      if (received == 0 ||
          (response.contentLength >= 0 && received != response.contentLength)) {
        throw const RemoteException('Download was incomplete.');
      }
    } finally {
      await sink.close();
    }
  }

  void close() => _http.close(force: true);
}
