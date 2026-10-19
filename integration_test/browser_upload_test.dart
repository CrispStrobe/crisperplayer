import 'dart:convert';
import 'dart:io';
import 'package:crisperplayer/providers/providers.dart';
import 'package:crisperplayer/screens/browser_upload_screen.dart';
import 'package:crisperplayer/services/db/app_database.dart';
import 'package:crisperplayer/services/library_service.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import '../test/support/audio_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native upload screen, WAV import and foreground-only lifecycle',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'crisper-upload-native-',
      );
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final library = LibraryService(db, storageDirectory: () async => root);
      final client = HttpClient();
      try {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [libraryServiceProvider.overrideWithValue(library)],
            child: const MaterialApp(home: BrowserUploadScreen()),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Start sharing'));
        await tester.tap(find.text('Start sharing'));
        await tester.pumpAndSettle();
        final displayed = tester
            .widgetList<SelectableText>(find.byType(SelectableText))
            .map((widget) => widget.data!)
            .toList();
        final address = Uri.parse(
          displayed.firstWhere((value) => value.startsWith('http://')),
        );
        await tester.scrollUntilVisible(
          find.text('Copy access code'),
          160,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        final code = tester
            .widgetList<SelectableText>(find.byType(SelectableText))
            .map((widget) => widget.data!)
            .singleWhere((value) => RegExp(r'^[a-f0-9]{40}$').hasMatch(value));
        final base = Uri.parse('http://127.0.0.1:${address.port}');
        final fixture = await writeTestWav(
          File('${root.path}/source.wav'),
          seconds: 2,
        );
        final bytes = await fixture.readAsBytes();
        final upload = await client.putUrl(
          base.resolve('/upload?name=Transferred.wav'),
        );
        upload.headers.set('Authorization', 'Bearer $code');
        upload.contentLength = bytes.length;
        upload.add(bytes);
        final received = await upload.close();
        expect(received.statusCode, 200);
        await received.drain<void>();
        final request = await client.postUrl(
          base.resolve('/import?title=Browser%20upload'),
        );
        request.headers.set('Authorization', 'Bearer $code');
        final response = await request.close();
        expect(response.statusCode, 200);
        expect(jsonDecode(await utf8.decoder.bind(response).join()), {
          'imported': true,
        });
        await fixture.delete();
        final book = (await db.allBooks).single;
        expect(book.title, 'Browser upload');
        expect(book.totalDurationMs, closeTo(2000, 100));
        final owned = File(AppDatabase.decodePaths(book.filePathsJson).single);
        expect(await owned.readAsBytes(), bytes);
        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
        for (final state in [
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        await tester.pumpAndSettle();
        expect(find.text('Start sharing'), findsOneWidget);
        await expectLater(() async {
          final request = await client.getUrl(base);
          await request.close();
        }(), throwsA(isA<SocketException>()));
        expect(await owned.exists(), isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        client.close(force: true);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await db.close();
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
