import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crisperplayer/services/audio/audio_metadata.dart';
import 'package:crisperplayer/services/library_service.dart';
import 'package:crisperplayer/services/db/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/quicktime_fixture.dart' show word;

List<int> little(int n) =>
    (ByteData(4)..setUint32(0, n, Endian.little)).buffer.asUint8List();
List<int> comments(List<String> entries, {String vendor = 'Crisper tests'}) => [
  ...little(utf8.encode(vendor).length),
  ...utf8.encode(vendor),
  ...little(entries.length),
  for (final entry in entries) ...[
    ...little(utf8.encode(entry).length),
    ...utf8.encode(entry),
  ],
];
final image = [137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 0];
List<int> picture() => [
  ...word(3),
  ...word(9),
  ...ascii.encode('image/png'),
  ...word(0),
  ...word(1),
  ...word(1),
  ...word(24),
  ...word(0),
  ...word(image.length),
  ...image,
];
List<int> flacBlock(int type, List<int> data, {bool last = false}) => [
  type | (last ? 128 : 0),
  data.length >> 16 & 255,
  data.length >> 8 & 255,
  data.length & 255,
  ...data,
];
List<int> oggPage(
  List<int> data,
  List<int> segments,
  int sequence, {
  int flags = 0,
}) => [
  ...ascii.encode('OggS'),
  0,
  flags,
  ...List.filled(8, 0),
  ...little(7),
  ...little(sequence),
  ...little(0),
  segments.length,
  ...segments,
  ...data,
];
List<int> ogg(List<int> packet, {bool opus = false}) {
  final id = opus ? ascii.encode('OpusHead') : [1, ...ascii.encode('vorbis')];
  final out = [
    ...oggPage(id, [id.length], 0, flags: 2),
  ];
  var offset = 0;
  var sequence = 1;
  while (offset < packet.length) {
    final count = (packet.length - offset).clamp(0, 255);
    final finalPart = offset + count == packet.length;
    out.addAll(
      oggPage(
        packet.sublist(offset, offset + count),
        [count, if (finalPart && count == 255) 0],
        sequence++,
        flags: offset > 0 ? 1 : 0,
      ),
    );
    offset += count;
  }
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(
    () async => root = await Directory.systemTemp.createTemp('vorbis-tags-'),
  );
  tearDown(() => root.delete(recursive: true));
  Future<File> write(String name, List<int> bytes) =>
      File('${root.path}/$name').writeAsBytes(bytes);
  final entries = [
    'TITLE=Track one',
    'ALBUM=Ozean 🎧',
    'ARTIST=作者',
    'artist=Second author',
    'CHAPTER001=00:00:00.000',
    'CHAPTER001NAME=Einführung',
    'CHAPTER002=00:05:30.125',
    'CHAPTER002NAME=第二章',
  ];
  test('FLAC comments, picture and chapter tags', () async {
    final file = await write('book.flac', [
      ...ascii.encode('fLaC'),
      ...flacBlock(0, List.filled(34, 0)),
      ...flacBlock(4, comments(entries)),
      ...flacBlock(6, picture(), last: true),
    ]);
    final result = await AudioMetadata.read(file.path);
    expect(result.title, 'Ozean 🎧');
    expect(result.author, '作者, Second author');
    expect(result.artwork, image);
    expect(result.chapters.map((c) => c.title), ['Einführung', '第二章']);
    expect(result.chapters.last.start.inMilliseconds, 330125);
  });
  for (final opus in [false, true]) {
    test(
      '${opus ? 'Opus' : 'Vorbis'} comments span Ogg pages and decode picture block',
      () async {
        final bytes = comments([
          ...entries,
          'METADATA_BLOCK_PICTURE=${base64Encode(picture())}',
        ], vendor: List.filled(400, 'x').join());
        final packet = [
          ...(opus ? ascii.encode('OpusTags') : [3, ...ascii.encode('vorbis')]),
          ...bytes,
        ];
        final file = await write(
          opus ? 'book.opus' : 'book.ogg',
          ogg(packet, opus: opus),
        );
        final result = await AudioMetadata.read(file.path);
        expect(result.title, 'Ozean 🎧');
        expect(result.artwork, image);
        expect(result.chapters, hasLength(2));
      },
    );
  }
  test(
    'damaged/truncated lengths and bad picture base64 preserve readable tags',
    () async {
      final file = await write('bad.flac', [
        ...ascii.encode('fLaC'),
        ...flacBlock(
          4,
          comments([
            'ALBUM=Still readable',
            'METADATA_BLOCK_PICTURE=not base64!',
            'CHAPTER001=99:99:99',
            'CHAPTER002=00:01:02.5',
          ]),
          last: true,
        ),
      ]);
      final result = await AudioMetadata.read(file.path);
      expect(result.title, 'Still readable');
      expect(result.artwork, isNull);
      expect(result.chapters.single.start.inMilliseconds, 62500);
      for (final bytes in [
        ascii.encode('fLaC'),
        [...ascii.encode('fLaC'), 132, 255, 255, 255, 1],
        ogg([3, ...ascii.encode('vorbis'), 255, 255, 255, 255]),
      ]) {
        await file.writeAsBytes(bytes);
        expect(await AudioMetadata.read(file.path), isA<AudioMetadata>());
      }
    },
  );
  test(
    'single-file import/refresh uses tagged chapters and measured final endpoint',
    () async {
      final source = await write('book.flac', [
        ...ascii.encode('fLaC'),
        ...flacBlock(4, comments(entries), last: true),
      ]);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      try {
        final library = LibraryService(
          db,
          storageDirectory: () async => root,
          probeDuration: (_) async => const Duration(minutes: 10),
        );
        final id = (await library.importFiles([source.path]))!;
        final chapters = await db.chaptersFor(id);
        expect(chapters, hasLength(2));
        expect(chapters.last.endMs, 600000);
        expect(await library.refreshChapters(id), isTrue);
        expect((await db.chaptersFor(id)).last.title, '第二章');
      } finally {
        await db.close();
      }
    },
  );
  test(
    'MP3 CHAP frames use nested Unicode titles and ignore nested CHAP recursion',
    () {
      List<int> frame(String id, List<int> data) => [
        ...ascii.encode(id),
        ...word(data.length),
        0,
        0,
        ...data,
      ];
      final chap = frame('CHAP', [
        ...ascii.encode('chapter1'),
        0,
        ...word(12000),
        ...word(25000),
        ...word(0xffffffff),
        ...word(0xffffffff),
        ...frame('TIT2', [3, ...utf8.encode('Kapitel 🎧')]),
        ...frame('CHAP', [0, ...List.filled(16, 0)]),
      ]);
      final header = [
        ...ascii.encode('ID3'),
        3,
        0,
        0,
        chap.length >> 21 & 127,
        chap.length >> 14 & 127,
        chap.length >> 7 & 127,
        chap.length & 127,
      ];
      final result = AudioMetadata.id3(
        Uint8List.fromList([...header, ...chap]),
      );
      expect(result.chapters.single.title, 'Kapitel 🎧');
      expect(result.chapters.single.start.inSeconds, 12);
      expect(result.chapters.single.end.inSeconds, 25);
    },
  );
}
