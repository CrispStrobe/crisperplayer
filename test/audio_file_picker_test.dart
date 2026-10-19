import 'dart:io';
import 'package:crisperplayer/services/db/app_database.dart';
import 'package:crisperplayer/services/library_service.dart';
import 'package:crisperplayer/utils/folder_import.dart';
import 'package:crisperplayer/screens/onboarding_screen.dart';
import 'package:crisperplayer/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/native.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

final class PickedAudio extends PlatformFile {
  PickedAudio(this.name, this.uri);
  @override
  final String name;
  @override
  final Uri uri;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class RecordingPicker extends FilePickerPlatform {
  List<PlatformFile> files = [];
  FileType? requestedType;
  List<String>? extensions;
  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    requestedType = type;
    extensions = allowedExtensions;
    return files;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late LibraryService library;
  late RecordingPicker picker;
  late FilePickerPlatform original;
  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = LibraryService(db);
    original = FilePickerPlatform.instance;
    picker = RecordingPicker();
    FilePickerPlatform.instance = picker;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });
  tearDown(() async {
    FilePickerPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
    await db.close();
  });

  test(
    'Android accepts audiobook extensions without provider MIME filtering',
    () async {
      picker.files = [
        for (final ext in audioExtensions)
          PickedAudio(
            'Book${ext.toUpperCase()}',
            Uri.file('/cache/Book${ext.toUpperCase()}'),
          ),
      ];
      expect(await library.pickAudioFiles(), hasLength(audioExtensions.length));
      expect(picker.requestedType, FileType.any);
      expect(picker.extensions, isNull);
    },
  );
  test('desktop retains native extension filtering', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    expect(await library.pickAudioFiles(), isEmpty);
    expect(picker.requestedType, FileType.custom);
    expect(picker.extensions, containsAll(['m4b', 'mp3', 'opus']));
  });
  testWidgets('onboarding displays unsupported selection errors', (
    tester,
  ) async {
    picker.files = [PickedAudio('notes.pdf', Uri.file('/cache/notes.pdf'))];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryServiceProvider.overrideWithValue(library),
          appDatabaseProvider.overrideWithValue(db),
          libraryBooksProvider.overrideWith((ref) => Stream.value(<Book>[])),
        ],
        child: const MaterialApp(home: OnboardingScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Import audiobooks'));
    await tester.tap(find.text('Import audiobooks'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Unsupported selection: notes.pdf'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;
  });

  test('cancel is harmless', () async {
    expect(await library.pickAudioFiles(), isEmpty);
  });
  test(
    'mixed unsupported selection fails explicitly before partial import',
    () async {
      picker.files = [
        PickedAudio('book.m4b', Uri.file('/cache/book.m4b')),
        PickedAudio('notes.pdf', Uri.file('/cache/notes.pdf')),
      ];
      await expectLater(
        library.pickAudioFiles(),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('notes.pdf'),
          ),
        ),
      );
      expect(await db.allBooks, isEmpty);
    },
  );
  test(
    'provider URI without a local copy fails instead of silently dropping book',
    () async {
      picker.files = [
        PickedAudio('book.m4b', Uri.parse('content://provider/book')),
      ];
      await expectLater(
        library.pickAudioFiles(),
        throwsA(isA<FileSystemException>()),
      );
    },
  );
}
