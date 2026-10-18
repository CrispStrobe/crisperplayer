import 'dart:async';
import 'dart:io';
import 'package:crisperplayer/services/db/app_database.dart';
import 'package:crisperplayer/services/library_service.dart';
import 'package:crisperplayer/services/share_intake_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'rebinding callbacks works and concurrent cold/warm delivery imports once',
      () async {
    final dir = await Directory.systemTemp.createTemp('crisper_share_');
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final stream = StreamController<List<SharedMediaFile>>.broadcast();
    final probe = Completer<Duration?>();
    final file = await File('${dir.path}/book.mp3').writeAsBytes([1, 2]);
    final shared = [
      SharedMediaFile(path: file.path, type: SharedMediaType.file)
    ];
    final library = LibraryService(db,
        storageDirectory: () async => Directory('${dir.path}/owned'),
        probeDuration: (_) => probe.future);
    var resets = 0;
    var calls = 0;
    List<SharedMediaFile> pending = [];
    final service = ShareIntakeService(
        library: library,
        initialMedia: () async => pending,
        mediaStream: stream.stream,
        resetMedia: () async {
          pending = [];
          resets++;
        });
    try {
      await service.init();
      await service.init(onImported: (id, _) async {
        expect(id, isNotNull);
        calls++;
      });
      pending = shared;
      final first = service.handleInitialMedia();
      await Future<void>.delayed(Duration.zero);
      final second = service.handleInitialMedia();
      stream.add(shared);
      await Future<void>.delayed(Duration.zero);
      probe.complete(const Duration(seconds: 10));
      await first;
      await second;
      expect(await db.allBooks, hasLength(1));
      expect(calls, 1);
      expect(resets, 1);
    } finally {
      await service.dispose();
      await stream.close();
      await db.close();
      await dir.delete(recursive: true);
    }
  });
}
