import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_storage/crisp_storage.dart' as shared;
// SmbSession's interface; not re-exported by crisp_storage.
// ignore: implementation_imports
import 'package:crisp_storage/src/smb_transport.dart' show SmbTransport;
import 'package:crypto/crypto.dart';

/// A session under test plus the engine it actually used.
typedef SmbCheckSession = ({
  SmbTransport transport,
  shared.SmbBackend? Function() effectiveBackend,
});

typedef SmbCheckSessionFactory =
    SmbCheckSession Function(
      shared.RemoteConnection connection,
      shared.SmbBackend engine,
    );

SmbCheckSession defaultSmbCheckSession(
  shared.RemoteConnection connection,
  shared.SmbBackend engine,
) {
  final session = shared.SmbSession(connection, backend: engine);
  return (transport: session, effectiveBackend: () => session.effectiveBackend);
}

/// Qualifies an SMB server with each engine, so a NAS can be checked from
/// the CLI without a development setup: connect + list, optional download
/// throughput and checksum of a real file, and an optional write round trip
/// (mkdir, write, read back, rename, delete) inside a scratch folder.
///
/// Credentials are never part of the report. Every step records its time
/// and either a detail or the error, and one failing engine does not stop
/// the others.
class SmbCheck {
  final SmbCheckSessionFactory openSession;
  final Directory Function() tempRoot;
  final DateTime Function() now;
  SmbCheck({
    this.openSession = defaultSmbCheckSession,
    Directory Function()? tempRoot,
    DateTime Function()? now,
  }) : tempRoot = tempRoot ?? (() => Directory.systemTemp),
       now = now ?? DateTime.now;

  static const writeSize = 1024 * 1024 + 7;

  Future<Map<String, Object?>> run({
    required String url,
    required String username,
    required String secret,
    bool requireEncryption = true,
    List<shared.SmbBackend> engines = const [
      shared.SmbBackend.libsmb2,
      shared.SmbBackend.rust,
    ],
    String? file,
    bool write = false,
    int downloadLimit = 4 * 1024 * 1024 * 1024,
  }) async {
    final connection = shared.RemoteConnection(
      id: 'smb-check',
      name: 'SMB check',
      kind: 'smb',
      url: url,
      username: username,
      secret: secret,
      requireEncryption: requireEncryption,
    );
    final results = <Map<String, Object?>>[];
    for (final engine in engines) {
      results.add(
        await _engine(connection, engine, file, write, downloadLimit),
      );
    }
    return {
      'url': connection.url.toString(),
      'username': username,
      'requireEncryption': requireEncryption,
      'ok': results.every((r) => r['ok'] == true),
      'engines': results,
    };
  }

  Future<Map<String, Object?>> _engine(
    shared.RemoteConnection connection,
    shared.SmbBackend engine,
    String? file,
    bool write,
    int downloadLimit,
  ) async {
    final steps = <Map<String, Object?>>[];
    final result = <String, Object?>{'engine': engine.name, 'steps': steps};
    SmbCheckSession? session;
    Future<T?> step<T>(
      String name,
      Future<T> Function() action, {
      Object? Function(T value)? detail,
    }) async {
      final watch = Stopwatch()..start();
      try {
        final value = await action();
        steps.add({
          'step': name,
          'ok': true,
          'ms': watch.elapsedMilliseconds,
          if (detail != null) 'detail': detail(value),
        });
        return value;
      } catch (error) {
        steps.add({
          'step': name,
          'ok': false,
          'ms': watch.elapsedMilliseconds,
          'error': _describe(error),
        });
        return null;
      }
    }

    try {
      session = openSession(connection, engine);
      final transport = session.transport;
      final listing = await step(
        'connect and list',
        () => transport.browse(transport.urlForPath('/')),
        detail: (List<shared.RemoteEntry> entries) => {
          'entries': entries.length,
          'folders': entries.where((e) => e.type == 'folder').length,
        },
      );
      result['effectiveBackend'] = session.effectiveBackend()?.name;
      if (session.effectiveBackend() == shared.SmbBackend.rust) {
        result['rustLibrary'] = shared.rustSmbLibraryLocation;
      }
      if (listing != null && file != null) {
        await _download(transport, file, downloadLimit, step);
      }
      if (listing != null && write) {
        await _writeRoundTrip(transport, engine, step);
      }
    } catch (error) {
      steps.add({
        'step': 'open session',
        'ok': false,
        'error': _describe(error),
      });
    } finally {
      session?.transport.close();
    }
    result['ok'] = steps.isNotEmpty && steps.every((s) => s['ok'] == true);
    return result;
  }

  Future<void> _download(
    SmbTransport transport,
    String file,
    int limit,
    Future<T?> Function<T>(
      String,
      Future<T> Function(), {
      Object? Function(T)? detail,
    })
    step,
  ) async {
    final url = transport.urlForPath(file);
    final entry = await step('stat file', () async {
      final entry = await transport.stat(url);
      if (entry == null) throw StateError('File not found: $file');
      if (entry.type != 'file') throw StateError('Not a file: $file');
      return entry;
    }, detail: (shared.RemoteEntry e) => {'bytes': e.size});
    if (entry == null) return;
    final dir = await tempRoot().createTemp('crisper-smb-check-');
    try {
      final out = File('${dir.path}/download');
      final watch = Stopwatch()..start();
      await step('download', () async {
        await transport.download(url, out, limit: limit);
        final bytes = await out.length();
        final seconds = watch.elapsedMicroseconds / 1e6;
        return {
          'bytes': bytes,
          'mibPerSecond': seconds <= 0
              ? null
              : double.parse((bytes / 1048576 / seconds).toStringAsFixed(2)),
          'sha256': (await sha256.bind(out.openRead()).first).toString(),
          if (entry.size != null && entry.size != bytes)
            'sizeMismatch': entry.size,
        };
      }, detail: (Map<String, Object?> d) => d);
    } finally {
      await dir.delete(recursive: true);
    }
  }

  Future<void> _writeRoundTrip(
    SmbTransport transport,
    shared.SmbBackend engine,
    Future<T?> Function<T>(
      String,
      Future<T> Function(), {
      Object? Function(T)? detail,
    })
    step,
  ) async {
    final folder =
        '/.crisperplayer-smb-check-${engine.name}-${now().millisecondsSinceEpoch}';
    final data = Uint8List.fromList(
      List.generate(writeSize, (i) => (i * 31 + 7) % 256),
    );
    final created = await step(
      'create scratch folder',
      () => transport.mkdir(transport.urlForPath(folder)).then((_) => true),
      detail: (_) => folder,
    );
    if (created != true) return;
    try {
      final written = await step(
        'write 1 MiB',
        () => transport
            .write(transport.urlForPath('$folder/probe.bin'), data)
            .then((_) => true),
      );
      if (written == true) {
        await step('read back', () async {
          final back = BytesBuilder(copy: false);
          await for (final chunk in transport.stream(
            transport.urlForPath('$folder/probe.bin'),
          )) {
            back.add(chunk);
          }
          final bytes = back.takeBytes();
          if (sha256.convert(bytes) != sha256.convert(data)) {
            throw StateError(
              'Read back ${bytes.length} bytes that differ from the '
              '${data.length} written',
            );
          }
          return bytes.length;
        }, detail: (int n) => {'bytes': n});
        await step(
          'rename',
          () => transport
              .rename(
                transport.urlForPath('$folder/probe.bin'),
                transport.urlForPath('$folder/renamed.bin'),
              )
              .then((_) => true),
        );
      }
    } finally {
      await step('clean up', () async {
        for (final entry in await transport.browse(
          transport.urlForPath(folder),
        )) {
          await transport.delete(
            transport.urlForPath('$folder/${entry.name}'),
            directory: false,
          );
        }
        await transport.delete(transport.urlForPath(folder), directory: true);
        return true;
      });
    }
  }

  static String _describe(Object error) {
    if (error is shared.RemoteException) {
      final code = error.code?.name;
      return code == null ? error.message : '${error.message} [$code]';
    }
    return '$error';
  }
}

/// Plain-text summary of an [SmbCheck.run] report for terminals.
String formatSmbCheck(Map<String, Object?> report) {
  final out = StringBuffer()
    ..writeln(
      'SMB check ${report['url']} (encryption '
      '${report['requireEncryption'] == true ? 'required' : 'optional'}): '
      '${report['ok'] == true ? 'OK' : 'FAILED'}',
    );
  for (final engine in (report['engines'] as List).cast<Map>()) {
    out.writeln(
      '\n[${engine['engine']}] ${engine['ok'] == true ? 'OK' : 'FAILED'}'
      '${engine['effectiveBackend'] == null ? '' : ' (used ${engine['effectiveBackend']})'}',
    );
    for (final step in (engine['steps'] as List).cast<Map>()) {
      final mark = step['ok'] == true ? '✓' : '✗';
      final info = step['ok'] == true ? step['detail'] : step['error'];
      out.writeln(
        '  $mark ${step['step']} (${step['ms'] ?? '-'} ms)${info == null ? '' : ': $info'}',
      );
    }
  }
  return out.toString();
}
