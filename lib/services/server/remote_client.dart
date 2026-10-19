import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crisp_storage/crisp_storage.dart' as shared;
import 'package:filen_client/filen_client.dart' as filen;
import 'package:internxt_client/internxt_client.dart' as internxt;
import 'package:path/path.dart' as p;
import 'package:crypto/crypto.dart';
import '../../utils/folder_import.dart';
export 'package:crisp_storage/crisp_storage.dart'
    show RemoteException, RemoteEntry;

/// Reuses CrispCloud's transports and encrypted provider clients. Session keys
/// are serialized only by the caller's platform credential store.
class RemoteConnection implements shared.RemoteConnection {
  final shared.RemoteConnection _base;
  @override
  final String kind;
  @override
  String get id => _base.id;
  @override
  String get name => _base.name;
  @override
  String get username => _base.username;
  @override
  String get secret => _base.secret;
  @override
  Uri get url => _base.url;
  @override
  bool get allowLocalHttp => _base.allowLocalHttp;
  @override
  bool get requireEncryption => _base.requireEncryption;
  @override
  String? get hostKey => _base.hostKey;
  static const cloudKinds = {'filen', 'internxt'};
  RemoteConnection({
    required String id,
    required String name,
    required this.kind,
    required String url,
    String username = '',
    required String secret,
    bool allowLocalHttp = false,
    bool requireEncryption = true,
    String? hostKey,
  }) : _base = shared.RemoteConnection(
         id: id,
         name: name,
         username: username,
         secret: secret,
         allowLocalHttp: allowLocalHttp,
         requireEncryption: requireEncryption,
         hostKey: hostKey,
         kind: cloudKinds.contains(kind) || kind == 'nextcloud'
             ? 'webdav'
             : kind,
         url: cloudKinds.contains(kind)
             ? cloudUrl(kind)
             : kind == 'nextcloud'
             ? nextcloudUrl(url, username)
             : url,
       );
  @override
  Map<String, Object?> toJson({bool credentials = false}) => {
    ..._base.toJson(credentials: credentials),
    'kind': kind,
  };
  static bool isLocalHost(String host) =>
      shared.RemoteConnection.isLocalHost(host);
  static String cloudUrl(String kind) => kind == 'filen'
      ? 'https://gateway.filen.io/'
      : 'https://gateway.internxt.com/';
  static String nextcloudUrl(String url, String username) {
    if (username.trim().isEmpty) {
      throw const FormatException('Enter the Nextcloud username.');
    }
    final base = Uri.parse(url.trim());
    if (base.path.contains('/remote.php/dav/files/')) return url;
    return base
        .replace(
          path:
              '${base.path.replaceFirst(RegExp(r'/+$'), '')}/remote.php/dav/files/${Uri.encodeComponent(username)}/',
        )
        .toString();
  }

  factory RemoteConnection.fromJson(Map<String, dynamic> row) =>
      RemoteConnection(
        id: row['id'] as String,
        name: row['name'] as String,
        kind: row['kind'] as String,
        url: row['url'] as String,
        username: row['username'] as String? ?? '',
        secret: row['secret'] as String,
        allowLocalHttp: row['allowLocalHttp'] == true,
        requireEncryption: row['requireEncryption'] != false,
        hostKey: row['hostKey'] as String?,
      );
  shared.RemoteConnection get transport => _base;
}

class _InternxtMemoryStorage implements internxt.ConfigStorage {
  final _values = <String, String>{};
  final Future<void> Function(String)? onCredentials;
  _InternxtMemoryStorage({this.onCredentials});
  void seed(String key, String value) {
    _values[key] = value;
  }

  @override
  void init(String dataDir, List<String> subDirs) {}
  @override
  Future<bool> exists(String key) async => _values.containsKey(key);
  @override
  Future<String?> read(String key) async => _values[key];
  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
    if (p.basename(key) == '.inxtcli-dart-creds.json') {
      await onCredentials?.call(value);
    }
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

class RemoteClient {
  final RemoteConnection connection;
  final Future<void> Function(String)? onSessionChanged;
  shared.RemoteClient? _transport;
  filen.FilenClient? _filen;
  internxt.InternxtClient? _internxt;
  Directory? _temporary;
  bool _closed = false;
  bool _downloading = false;
  RemoteClient(
    this.connection, {
    HttpClient? httpClient,
    this.onSessionChanged,
  }) {
    if (!RemoteConnection.cloudKinds.contains(connection.kind)) {
      _transport = shared.RemoteClient(
        connection.transport,
        httpClient: httpClient,
      );
    }
  }
  static bool isAudio(String name) => shared.RemoteClient.isAudio(name);
  Uri uri(String path) {
    if (_transport != null) return _transport!.uri(path);
    final raw = Uri.decodeComponent(path).split('/');
    if (raw.any((v) => v == '..' || v == '.')) {
      throw const FormatException('Invalid cloud path.');
    }
    final parsed = Uri.parse(path);
    if (parsed.hasScheme ||
        parsed.hasAuthority ||
        parsed.hasQuery ||
        parsed.hasFragment ||
        parsed.pathSegments.any(
          (v) =>
              v == '..' ||
              v == '.' ||
              v.contains('/') ||
              v.contains('\\') ||
              v.contains('\u0000'),
        )) {
      throw const FormatException('Invalid cloud path.');
    }
    return connection.url.resolve(path);
  }

  Future<void> _session() async {
    if (_closed) throw const shared.RemoteException('Connection closed.');
    if (_filen != null || _internxt != null) return;
    // Filen's configuration creates directories even with injected storage.
    // Use a disposable directory and memory storage: never the SDK's HOME default.
    _temporary = await Directory.systemTemp.createTemp('crisper-cloud-');
    final auth = (jsonDecode(connection.secret) as Map).cast<String, dynamic>();
    if (connection.kind == 'filen') {
      _filen = filen.FilenClient(
        config: filen.ConfigService(
          configPath: _temporary!.path,
          storage: filen.InMemoryConfigStorage(),
        ),
      )..setAuth(auth);
    } else {
      final storage = _InternxtMemoryStorage(onCredentials: onSessionChanged);
      final config = internxt.ConfigService(
        configPath: _temporary!.path,
        storage: storage,
      );
      storage.seed(config.credentialsFile, connection.secret);
      _internxt = internxt.InternxtClient(config: config)..setAuth(auth);
    }
  }

  static Future<String> authenticate(
    String kind,
    String email,
    String password,
    String? code,
  ) async {
    final temp = await Directory.systemTemp.createTemp('crisper-cloud-login-');
    try {
      Map<String, dynamic> auth;
      if (kind == 'filen') {
        final client = filen.FilenClient(
          config: filen.ConfigService(
            configPath: temp.path,
            storage: filen.InMemoryConfigStorage(),
          ),
        );
        auth = await client.login(email, password, twoFactorCode: code ?? '');
        client.setAuth(auth);
        auth['baseFolderUUID'] =
            auth['baseFolderUUID'] ?? await client.fetchBaseFolderUUID();
      } else {
        final client = internxt.InternxtClient(
          config: internxt.ConfigService(
            configPath: temp.path,
            storage: _InternxtMemoryStorage(),
          ),
        );
        auth = await client.login(email, password, tfaCode: code);
      }
      auth['email'] = email;
      return jsonEncode(auth);
    } finally {
      await temp.delete(recursive: true);
    }
  }

  Future<List<shared.RemoteEntry>> browse(String path) async {
    if (_transport != null) return _transport!.browse(path);
    uri(path);
    await _session();
    final root = path.isEmpty ? '/' : path;
    Map<String, dynamic> rows;
    if (_filen != null) {
      final resolved = await _filen!.resolvePath(root);
      if (resolved['type'] != 'folder') {
        throw const shared.RemoteException('Select a cloud folder.');
      }
      rows = {
        'folders': await _filen!.listFoldersAsync(
          resolved['uuid'] as String,
          detailed: true,
        ),
        'files': await _filen!.listFolderFiles(
          resolved['uuid'] as String,
          detailed: true,
        ),
      };
    } else {
      rows = await _internxt!.listPath(root);
    }
    final entries = <shared.RemoteEntry>[];
    for (final category in ['folders', 'files']) {
      for (final row in (rows[category] as List? ?? [])) {
        final name = row['name'] as String;
        if (name.isEmpty ||
            name == '.' ||
            name == '..' ||
            name.contains('/') ||
            name.contains('\\')) {
          throw const shared.RemoteException('Invalid cloud entry name.');
        }
        entries.add(
          shared.RemoteEntry(
            p.posix.join(root, name),
            name,
            category == 'folders' ? 'folder' : 'file',
            size: int.tryParse('${row['size']}'),
          ),
        );
      }
    }
    entries.sort((a, b) => naturalPathCompare(a.name, b.name));
    return entries;
  }

  Future<List<shared.RemoteEntry>> tracks(String path) async =>
      _transport != null
      ? _transport!.tracks(path)
      : (await browse(
          path,
        )).where((e) => e.type == 'file' && isAudio(e.name)).toList();
  Future<void> download(
    String path,
    File output, {
    void Function(int)? onBytes,
    int limit = 64 * 1024 * 1024 * 1024,
  }) async {
    if (_transport != null) {
      return _transport!.download(path, output, onBytes: onBytes, limit: limit);
    }
    uri(path);
    await _session();
    // SDKs stream decrypted chunks to a private staging directory. Completed
    // output becomes visible atomically; an interrupted encrypted file restarts.
    final info = _filen != null
        ? await _filen!.resolvePath(path)
        : await _internxt!.resolvePath(path);
    final metadata = (info['metadata'] as Map?) ?? info;
    final size = int.tryParse('${metadata['size']}');
    if (size != null && size > limit) {
      throw const shared.RemoteException('Cloud file exceeds size limit.');
    }
    final identity = jsonEncode({
      'provider': connection.kind,
      'account': connection.username,
      'path': path,
      'uuid': info['uuid'],
      'size': size,
      'modified':
          metadata['lastModified'] ??
          metadata['updatedAt'] ??
          metadata['timestamp'],
    });
    final marker = File('${output.path}.cloud.json');
    if (size != null && await output.exists() && await marker.exists()) {
      try {
        final saved = jsonDecode(await marker.readAsString()) as Map;
        if (saved['identity'] == identity &&
            await output.length() == size &&
            saved['sha256'] ==
                (await sha256.bind(output.openRead()).first).toString()) {
          onBytes?.call(size);
          return;
        }
      } on FormatException {
        /* Invalid staging metadata is disposable. */
      }
    }
    _downloading = true;
    final stage = await _temporary!.createTemp('audio-');
    final target = File(p.join(stage.path, 'audio'));
    try {
      if (_filen != null) {
        await _filen!.downloadFile(
          info['uuid'] as String,
          savePath: target.path,
          onProgress: (done, total) {
            if (_closed || done > limit || total > limit) {
              throw const shared.RemoteException(
                'Download paused or exceeds size limit.',
              );
            }
            onBytes?.call(done);
          },
        );
      } else {
        await _internxt!.downloadFileByPath(
          path,
          target.path,
          onConflict: 'overwrite',
        );
      }
      if (_closed) throw const shared.RemoteException('Download paused.');
      final length = await target.length();
      if (length > limit) {
        throw const shared.RemoteException('Cloud file exceeds size limit.');
      }
      if (size != null && length != size) {
        throw const shared.RemoteException(
          'Cloud download size did not match its metadata.',
        );
      }
      // Temp and app storage can be on different volumes.
      final part = await target.copy('${output.path}.cloud-part');
      await part.rename(output.path);
      final checksum = (await sha256.bind(output.openRead()).first).toString();
      final markerPart = File('${marker.path}.tmp');
      await markerPart.writeAsString(
        jsonEncode({'identity': identity, 'sha256': checksum}),
        flush: true,
      );
      await markerPart.rename(marker.path);
      onBytes?.call(length);
    } finally {
      _downloading = false;
      if (await stage.exists()) await stage.delete(recursive: true);
      if (_closed && await _temporary!.exists()) {
        await _temporary!.delete(recursive: true);
      }
    }
  }

  /// Small, private metadata objects only; audiobook uploads are not exposed.
  Future<void> putMetadata(String folder, String name, List<int> bytes) async {
    if (bytes.length > 5 * 1024 * 1024 ||
        !RegExp(r'^crisper-state-[a-zA-Z0-9-]+[.]json$').hasMatch(name)) {
      throw const FormatException('Invalid progress metadata.');
    }
    uri(folder);
    if (RemoteConnection.cloudKinds.contains(connection.kind)) {
      await _session();
      if (_filen != null) {
        final target = await _filen!.resolvePath(folder.isEmpty ? '/' : folder);
        await _filen!.uploadBytes(
          Uint8List.fromList(bytes),
          name,
          target['uuid'] as String,
        );
      } else {
        await _internxt!.uploadFileBytes(
          bytes,
          name,
          folder.isEmpty ? '/' : folder,
        );
      }
    } else {
      if (!{'webdav', 'nextcloud'}.contains(connection.kind)) {
        throw const FormatException(
          'Use Nextcloud, WebDAV, Filen or Internxt for progress sync.',
        );
      }
      await _metadataRequest('PUT', _metadataPath(folder, name), bytes: bytes);
    }
  }

  String _metadataPath(String folder, String name) {
    final base = folder.isEmpty ? connection.url.path : folder;
    final path = base.endsWith('/') ? base : '$base/';
    return '$path${Uri.encodeComponent(name)}';
  }

  Future<void> deleteMetadata(String folder, String name) async {
    if (!RegExp(r'^crisper-state-[a-zA-Z0-9-]+[.]json$').hasMatch(name)) {
      throw const FormatException('Invalid metadata name.');
    }
    uri(folder);
    if (RemoteConnection.cloudKinds.contains(connection.kind)) {
      await _session();
      final path = p.posix.join(folder.isEmpty ? '/' : folder, name);
      if (_filen != null) {
        await _filen!.trashByPath(path);
      } else {
        await _internxt!.deletePath(path);
      }
    } else {
      await _metadataRequest('DELETE', _metadataPath(folder, name));
    }
  }

  Future<void> _metadataRequest(
    String method,
    String path, {
    List<int>? bytes,
  }) async {
    if (!{'webdav', 'nextcloud'}.contains(connection.kind)) {
      throw const FormatException(
        'Metadata writes require a cloud provider or WebDAV.',
      );
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client
          .openUrl(method, uri(path))
          .timeout(const Duration(seconds: 15));
      req.followRedirects = false;
      req.headers.set(
        'Authorization',
        'Basic ${base64Encode(utf8.encode('${connection.username}:${connection.secret}'))}',
      );
      if (bytes != null) {
        req.headers.contentType = ContentType.json;
        req.contentLength = bytes.length;
        req.add(bytes);
      }
      final response = await req.close().timeout(const Duration(seconds: 20));
      await response.drain<void>().timeout(const Duration(seconds: 10));
      if (![200, 201, 204].contains(response.statusCode)) {
        throw const shared.RemoteException(
          'Could not write progress metadata.',
        );
      }
    } finally {
      client.close(force: true);
    }
  }

  void close() {
    _closed = true;
    _transport?.close();
    // Active SDK operations may still own this directory. Deletion is deferred
    // to their finally block and a new session never reuses it.
    final temp = _temporary;
    if (temp != null && !_downloading) temp.delete(recursive: true).ignore();
  }
}
