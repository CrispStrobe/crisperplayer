import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crisp_storage/crisp_storage.dart';
// ignore: implementation_imports
import 'package:crisp_storage/src/smb_transport.dart' show SmbTransport;
import 'package:crisperplayer/cli/control_client.dart';
import 'package:crisperplayer/services/desktop_control_service.dart';
import 'package:crisperplayer/services/server/credential_store.dart';
import 'package:crisperplayer/services/server/remote_library_service.dart';
import 'package:crisperplayer/services/server/smb_check.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/playback_harness.dart';

/// In-memory SMB share: path -> bytes (files) or null (folders).
class _FakeShare implements SmbTransport {
  final Map<String, Uint8List?> items;
  final String base = 'smb://nas/Books/';
  bool failConnect = false;
  bool corruptReads = false;
  bool failWrite = false;
  bool closed = false;
  final calls = <String>[];
  _FakeShare(this.items);

  String _rel(String url) {
    final path = url.substring(base.length).replaceAll(RegExp(r'/+$'), '');
    return Uri.decodeComponent(path);
  }

  @override
  String urlForPath(String path) =>
      base +
      path
          .split('/')
          .where((s) => s.isNotEmpty)
          .map(Uri.encodeComponent)
          .join('/');

  @override
  Future<List<RemoteEntry>> browse(String path) async {
    calls.add('browse ${_rel(path)}');
    if (failConnect) {
      throw const RemoteException('auth', code: RemoteErrorCode.smbAuth);
    }
    final dir = _rel(path);
    final prefix = dir.isEmpty ? '' : '$dir/';
    return [
      for (final e in items.entries)
        if (e.key.startsWith(prefix) &&
            e.key != dir &&
            !e.key.substring(prefix.length).contains('/'))
          RemoteEntry(
            urlForPath(e.key),
            e.key.substring(prefix.length),
            e.value == null ? 'folder' : 'file',
            size: e.value?.length ?? 0,
          ),
    ];
  }

  @override
  Future<RemoteEntry?> stat(String path) async {
    final rel = _rel(path);
    if (!items.containsKey(rel)) return null;
    final v = items[rel];
    return RemoteEntry(
      path,
      rel.split('/').last,
      v == null ? 'folder' : 'file',
      size: v?.length ?? 0,
    );
  }

  @override
  Stream<List<int>> stream(
    String path, {
    void Function(int, int)? onProgress,
  }) async* {
    final data = items[_rel(path)]!;
    yield corruptReads ? (Uint8List.fromList(data)..[0] ^= 1) : data;
  }

  @override
  Future<void> download(
    String path,
    File output, {
    void Function(int)? onBytes,
    required int limit,
  }) async {
    final data = items[_rel(path)]!;
    if (data.length > limit) throw StateError('limit');
    await output.writeAsBytes(data);
  }

  @override
  Future<void> write(String path, Uint8List bytes) async {
    calls.add('write ${_rel(path)}');
    if (failWrite) {
      throw const RemoteException('denied', code: RemoteErrorCode.accessDenied);
    }
    items[_rel(path)] = bytes;
  }

  @override
  Future<void> upload(String path, Stream<List<int>> data) async =>
      write(path, Uint8List.fromList(await data.expand((e) => e).toList()));

  @override
  Future<void> mkdir(String path) async {
    calls.add('mkdir ${_rel(path)}');
    items[_rel(path)] = null;
  }

  @override
  Future<void> rename(String from, String to) async {
    calls.add('rename ${_rel(from)} -> ${_rel(to)}');
    items[_rel(to)] = items.remove(_rel(from));
  }

  @override
  Future<void> delete(String path, {required bool directory}) async {
    calls.add('delete ${_rel(path)}');
    items.remove(_rel(path));
  }

  @override
  void close() => closed = true;
}

class _NoCredentials implements ServerCredentialStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String next) async {}
  @override
  Future<void> delete() async {}
}

/// Records what the CLI asks for instead of talking to servers.
class _RecordingRemote extends RemoteLibraryService {
  final calls = <Map<String, Object?>>[];
  _RecordingRemote(super.library) : super(credentials: _NoCredentials());

  @override
  Future<void> connect({
    required String name,
    required String kind,
    required String url,
    required String secret,
    String username = '',
    bool allowLocalHttp = false,
    bool requireEncryption = true,
    SmbBackend? smbBackend,
    String? hostKey,
    String? twoFactorCode,
  }) async => calls.add({
    'connect': kind,
    'name': name,
    'url': url,
    'secret': secret,
    'username': username,
    'allowLocalHttp': allowLocalHttp,
    'requireEncryption': requireEncryption,
    'smbBackend': smbBackend?.name,
    'hostKey': hostKey,
    'twoFactorCode': twoFactorCode,
  });

  @override
  Future<void> disconnect(String id) async => calls.add({'disconnect': id});

  @override
  Future<List<RemoteEntry>> browse(String id, String path) async {
    calls.add({'browse': id, 'path': path});
    return [RemoteEntry('$path/a.mp3', 'a.mp3', 'file', size: 3)];
  }

  @override
  Future<String> download(
    String connectionId,
    String path,
    String title, {
    String author = '',
    bool file = false,
  }) async {
    calls.add({
      'download': connectionId,
      'path': path,
      'title': title,
      'author': author,
      'file': file,
    });
    return 'book-1';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  final sample = Uint8List.fromList(List.generate(300000, (i) => i % 241));

  SmbCheck checkWith(Map<SmbBackend, _FakeShare> shares) => SmbCheck(
    openSession: (connection, engine) {
      expect(connection.requireEncryption, isTrue);
      final share = shares[engine]!;
      return (
        transport: share,
        effectiveBackend: () =>
            engine == SmbBackend.auto ? SmbBackend.rust : engine,
      );
    },
    now: () => DateTime.fromMillisecondsSinceEpoch(1700000000000),
  );

  Map<String, Uint8List?> share() => {
    'Audio': null,
    'Audio/Book 1.m4b': sample,
    'big.bin': sample,
  };

  test('passes every step and reports throughput and checksum', () async {
    final lib = _FakeShare(share()), rust = _FakeShare(share());
    final report =
        await checkWith({SmbBackend.libsmb2: lib, SmbBackend.rust: rust}).run(
          url: 'smb://nas/Books/',
          username: 'reader',
          secret: 'pw',
          file: '/Audio/Book 1.m4b',
          write: true,
        );
    expect(report['ok'], isTrue);
    final engines = (report['engines'] as List).cast<Map>();
    expect(engines.map((e) => e['engine']), ['libsmb2', 'rust']);
    expect(engines.map((e) => e['effectiveBackend']), ['libsmb2', 'rust']);
    for (final engine in engines) {
      final steps = {
        for (final s in (engine['steps'] as List).cast<Map>()) s['step']: s,
      };
      expect(steps.keys, [
        'connect and list',
        'stat file',
        'download',
        'create scratch folder',
        'write 1 MiB',
        'read back',
        'rename',
        'clean up',
      ]);
      expect(steps.values.every((s) => s['ok'] == true), isTrue);
      expect(steps['connect and list']!['detail'], {
        'entries': 2,
        'folders': 1,
      });
      final download = steps['download']!['detail'] as Map;
      expect(download['bytes'], sample.length);
      expect(download['sha256'], sha256.convert(sample).toString());
      expect(download.containsKey('sizeMismatch'), isFalse);
    }
    // The scratch folder is removed again and sessions are closed.
    expect(
      lib.items.keys.where((k) => k.startsWith('.crisperplayer')),
      isEmpty,
    );
    expect(lib.closed && rust.closed, isTrue);
    expect(
      lib.calls,
      contains('mkdir .crisperplayer-smb-check-libsmb2-1700000000000'),
    );
  });

  test('one failing engine does not stop the others', () async {
    final rust = _FakeShare(share())..failConnect = true;
    final report = await checkWith({
      SmbBackend.libsmb2: _FakeShare(share()),
      SmbBackend.rust: rust,
    }).run(url: 'smb://nas/Books/', username: 'r', secret: 'pw', write: true);
    expect(report['ok'], isFalse);
    final engines = (report['engines'] as List).cast<Map>();
    expect(engines[0]['ok'], isTrue);
    expect(engines[1]['ok'], isFalse);
    final steps = (engines[1]['steps'] as List).cast<Map>();
    expect(steps.single['step'], 'connect and list');
    expect(steps.single['error'], contains('[smbAuth]'));
    expect(rust.calls.where((c) => c.startsWith('mkdir')), isEmpty);
    expect(rust.closed, isTrue);
  });

  test('detects corrupted reads and still cleans up', () async {
    final lib = _FakeShare(share())..corruptReads = true;
    final report = await checkWith({SmbBackend.libsmb2: lib}).run(
      url: 'smb://nas/Books/',
      username: 'r',
      secret: 'pw',
      engines: const [SmbBackend.libsmb2],
      write: true,
    );
    final steps = ((report['engines'] as List).single['steps'] as List)
        .cast<Map>();
    final readBack = steps.firstWhere((s) => s['step'] == 'read back');
    expect(readBack['ok'], isFalse);
    expect(readBack['error'], contains('differ'));
    expect(steps.last['step'], 'clean up');
    expect(steps.last['ok'], isTrue);
    expect(
      lib.items.keys.where((k) => k.startsWith('.crisperplayer')),
      isEmpty,
    );
  });

  test('a failed write skips read and rename but still cleans up', () async {
    final lib = _FakeShare(share())..failWrite = true;
    final report = await checkWith({SmbBackend.libsmb2: lib}).run(
      url: 'smb://nas/Books/',
      username: 'r',
      secret: 'pw',
      engines: const [SmbBackend.libsmb2],
      write: true,
    );
    final names = [
      for (final s
          in ((report['engines'] as List).single['steps'] as List).cast<Map>())
        '${s['step']}:${s['ok']}',
    ];
    expect(names, [
      'connect and list:true',
      'create scratch folder:true',
      'write 1 MiB:false',
      'clean up:true',
    ]);
  });

  test('a missing sample file is a failed step, not a crash', () async {
    final report = await checkWith({SmbBackend.libsmb2: _FakeShare(share())})
        .run(
          url: 'smb://nas/Books/',
          username: 'r',
          secret: 'pw',
          engines: const [SmbBackend.libsmb2],
          file: '/nope.mp3',
        );
    final steps = ((report['engines'] as List).single['steps'] as List)
        .cast<Map>();
    expect(steps.last['step'], 'stat file');
    expect(steps.last['error'], contains('File not found'));
    expect(report['ok'], isFalse);
  });

  test('never includes the secret and formats a readable summary', () async {
    final report = await checkWith({SmbBackend.libsmb2: _FakeShare(share())})
        .run(
          url: 'smb://nas/Books/',
          username: 'reader',
          secret: 'very-secret-pw',
          engines: const [SmbBackend.libsmb2],
        );
    expect(jsonEncode(report), isNot(contains('very-secret-pw')));
    final text = formatSmbCheck(report);
    expect(
      text,
      contains('SMB check smb://nas/Books/ (encryption required): OK'),
    );
    expect(text, contains('[libsmb2] OK (used libsmb2)'));
    expect(text, contains('✓ connect and list'));
  });

  group('desktop control', () {
    late PlaybackHarness h;
    late DesktopControlService control;
    late ControlClient client;
    final requests = <Map<String, Object?>>[];

    setUp(() async {
      h = PlaybackHarness();
      await h.init();
      requests.clear();
      control = DesktopControlService(
        library: h.library,
        playback: h.playback,
        descriptor: File('${h.root.path}/cli.json'),
        smbCheck: SmbCheck(
          openSession: (connection, engine) {
            requests.add({
              'engine': engine.name,
              'url': connection.url.toString(),
              'user': connection.username,
              'secret': connection.secret,
              'encryption': connection.requireEncryption,
            });
            return (
              transport: _FakeShare(share()),
              effectiveBackend: () => engine,
            );
          },
        ),
      );
      await control.start();
      client = ControlClient(control.descriptor);
    });
    tearDown(() async => control.dispose());

    test(
      'smb-check runs on the diagnostics endpoint with all options',
      () async {
        final report =
            await client.command('smb-check', {
                  'url': 'smb://nas/Books/',
                  'username': 'reader',
                  'secret': 'pw',
                  'requireEncryption': false,
                  'engines': ['auto'],
                })
                as Map;
        expect(report['ok'], isTrue);
        expect(requests, [
          {
            'engine': 'auto',
            'url': 'smb://nas/Books/',
            'user': 'reader',
            'secret': 'pw',
            'encryption': false,
          },
        ]);
      },
    );

    test('rejects unknown engines', () async {
      await expectLater(
        client.command('smb-check', {
          'url': 'smb://nas/Books/',
          'username': 'r',
          'secret': 'pw',
          'engines': ['ntlmv1'],
        }),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'the CLI binary passes the secret via stdin and sets the exit code',
      () async {
        Future<ProcessResult> cli(List<String> args, {String? input}) async {
          final process = await Process.start(
            Platform.resolvedExecutable.contains('flutter_tester')
                ? 'dart'
                : Platform.resolvedExecutable,
            [
              'run',
              'bin/crisperplayer.dart',
              '--control-file',
              control.descriptor.path,
              ...args,
            ],
          );
          if (input != null) process.stdin.write(input);
          await process.stdin.close();
          final out = await process.stdout.transform(utf8.decoder).join();
          final err = await process.stderr.transform(utf8.decoder).join();
          return ProcessResult(process.pid, await process.exitCode, out, err);
        }

        final ok = await cli([
          'smb-check',
          'smb://nas/Books/',
          '--user',
          'reader',
          '--secret',
          '-',
          '--engines',
          'libsmb2',
        ], input: 'stdin-pw\n');
        expect(ok.exitCode, 0, reason: '${ok.stderr}');
        expect(ok.stdout, contains('[libsmb2] OK'));
        expect(requests.single['secret'], 'stdin-pw');

        final asJson = await cli([
          'smb-check',
          'smb://nas/Books/',
          '--user',
          'r',
          '--secret',
          '-',
          '--engines',
          'rust',
          '--json',
        ], input: 'pw\n');
        expect((jsonDecode(asJson.stdout as String) as Map)['ok'], isTrue);

        final argvSecret = await cli([
          'smb-check',
          'smb://nas/Books/',
          '--user',
          'r',
          '--secret',
          'plain',
        ]);
        expect(argvSecret.exitCode, 1);
        expect(argvSecret.stderr, contains('--secret -'));

        final typo = await cli([
          'smb-check',
          'smb://nas/Books/',
          '--user',
          'r',
          '--secret',
          '-',
          '--writ',
        ], input: 'pw\n');
        expect(typo.exitCode, 1);
        expect(typo.stderr, contains('Unexpected arguments: --writ'));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });

  group('server commands from the CLI binary', () {
    late PlaybackHarness h;
    late DesktopControlService control;
    late _RecordingRemote remote;

    setUp(() async {
      h = PlaybackHarness();
      await h.init();
      remote = _RecordingRemote(h.library);
      control = DesktopControlService(
        library: h.library,
        playback: h.playback,
        remote: remote,
        descriptor: File('${h.root.path}/cli.json'),
      );
      await control.start();
    });
    tearDown(() async {
      await control.dispose();
      remote.dispose();
    });

    Future<ProcessResult> cli(List<String> args, {String? input}) async {
      final process = await Process.start('dart', [
        'run',
        'bin/crisperplayer.dart',
        '--control-file',
        control.descriptor.path,
        ...args,
      ]);
      if (input != null) process.stdin.write(input);
      await process.stdin.close();
      final out = await process.stdout.transform(utf8.decoder).join();
      final err = await process.stderr.transform(utf8.decoder).join();
      return ProcessResult(process.pid, await process.exitCode, out, err);
    }

    test(
      'connect, browse, download and disconnect map to the service',
      () async {
        var r = await cli([
          'connect',
          'smb',
          'smb://nas/Books/',
          '--name',
          'NAS',
          '--user',
          r'HOME\reader',
          '--secret',
          '-',
          '--2fa',
          '-',
          '--smb-backend',
          'rust',
          '--no-encryption',
        ], input: 'pw from stdin\n123456\n');
        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(remote.calls.last, {
          'connect': 'smb',
          'name': 'NAS',
          'url': 'smb://nas/Books/',
          'secret': 'pw from stdin',
          'username': r'HOME\reader',
          'allowLocalHttp': false,
          'requireEncryption': false,
          'smbBackend': 'rust',
          'hostKey': null,
          'twoFactorCode': '123456',
        });

        r = await cli([
          'connect',
          'internxt',
          '--name',
          'Cloud',
          '--user',
          'me@x.y',
          '--secret',
          '-',
          '--2fa',
          '654321',
        ], input: 'cloud-pw\n');
        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(remote.calls.last['url'], '');
        expect(remote.calls.last['secret'], 'cloud-pw');
        expect(remote.calls.last['twoFactorCode'], '654321');
        expect(remote.calls.last['requireEncryption'], true);

        r = await cli(['browse', 'nas-id', '/Audio Books']);
        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(remote.calls.last, {'browse': 'nas-id', 'path': '/Audio Books'});
        expect(
          (jsonDecode(r.stdout as String) as List).single['name'],
          'a.mp3',
        );

        r = await cli([
          'download',
          'nas-id',
          '/Audio Books/a.mp3',
          '--title',
          'A Book',
          '--author',
          'Someone',
          '--file',
        ]);
        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(remote.calls.last, {
          'download': 'nas-id',
          'path': '/Audio Books/a.mp3',
          'title': 'A Book',
          'author': 'Someone',
          'file': true,
        });
        expect(jsonDecode(r.stdout as String), {'bookId': 'book-1'});

        r = await cli(['disconnect', 'nas-id']);
        expect(r.exitCode, 0, reason: '${r.stderr}');
        expect(remote.calls.last, {'disconnect': 'nas-id'});
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test(
      'rejects argv secrets, missing values and unknown arguments',
      () async {
        final before = remote.calls.length;
        for (final (args, message) in [
          (
            [
              'connect',
              'webdav',
              'https://x/',
              '--name',
              'W',
              '--secret',
              'plain',
            ],
            'stdin',
          ),
          (['connect', 'webdav', 'https://x/'], '--name is required'),
          (['download', 'id', '/a.mp3'], '--title is required'),
          (['browse'], 'ID is required'),
          (['browse', 'id', '/x', '--recursive'], 'Unexpected arguments'),
          (['disconnect', 'id', 'extra'], 'Unexpected arguments: extra'),
        ]) {
          final r = await cli(args);
          expect(r.exitCode, 1, reason: '$args');
          expect(r.stderr, contains(message), reason: '$args');
        }
        expect(remote.calls.length, before, reason: 'nothing reached the app');
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}
