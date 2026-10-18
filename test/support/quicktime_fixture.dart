import 'dart:convert';
import 'dart:typed_data';

Uint8List atom(String type, List<int> payload) => Uint8List.fromList([
  ...word(8 + payload.length),
  ...latin1.encode(type),
  ...payload,
]);
List<int> word(int n) => (ByteData(4)..setUint32(0, n)).buffer.asUint8List();
List<int> wide(int n) => (ByteData(8)..setUint64(0, n)).buffer.asUint8List();
List<int> textSample(List<int> text) => [
  text.length >> 8,
  text.length & 255,
  ...text,
];

// Three text samples in two chunks; a separate subtitle track deliberately has
// the same handler. Only the track referenced by the enabled audio is chapters.
({Uint8List moov, Uint8List data}) fixture({
  bool co64 = false,
  int base = 8,
  int sampleCount = 3,
  bool reference = true,
  bool truncateTiming = false,
  bool edit = false,
}) {
  final texts = [
    textSample(utf8.encode('Einführung 🎧')),
    textSample([0xfe, 0xff, 0x7b, 0x2c, 0x4e, 0x8c, 0x7a, 0xe0]), // 第二章
    textSample([0xff, 0xfe, 0x46, 0, 0xe9, 0, 0x65, 0]), // Fée
  ];
  final data = Uint8List.fromList([
    ...texts[0],
    ...texts[1],
    0,
    0,
    ...texts[2],
  ]);
  final tkhd = Uint8List(84)..[3] = 1;
  tkhd.setRange(12, 16, word(1));
  final audio = atom('trak', [
    ...atom('tkhd', tkhd),
    if (reference) ...atom('tref', atom('chap', word(2))),
  ]);
  final textHeader = Uint8List.fromList(tkhd)..[3] = 0;
  textHeader.setRange(12, 16, word(2));
  final mdhd = Uint8List(24);
  mdhd.setRange(12, 16, word(1000));
  final hdlr = Uint8List(24);
  hdlr.setRange(8, 12, ascii.encode('text'));
  final tables = atom('stbl', [
    ...atom('stsd', [
      0,
      0,
      0,
      0,
      ...word(1),
      ...atom('text', List.filled(8, 0)),
    ]),
    ...atom('stsz', [
      0,
      0,
      0,
      0,
      ...word(0),
      ...word(sampleCount),
      for (final t in texts) ...word(t.length),
    ]),
    ...atom('stts', [
      0,
      0,
      0,
      0,
      ...word(2),
      ...word(2),
      ...word(5000),
      if (!truncateTiming) ...[...word(1), ...word(10000)],
    ]),
    ...atom('stsc', [
      0,
      0,
      0,
      0,
      ...word(2),
      ...word(1),
      ...word(2),
      ...word(1),
      ...word(2),
      ...word(1),
      ...word(1),
    ]),
    ...atom(co64 ? 'co64' : 'stco', [
      0,
      0,
      0,
      0,
      ...word(2),
      ...(co64 ? wide(base) : word(base)),
      ...(co64
          ? wide(base + texts[0].length + texts[1].length + 2)
          : word(base + texts[0].length + texts[1].length + 2)),
    ]),
  ]);
  final text = atom('trak', [
    ...atom('tkhd', textHeader),
    if (edit)
      ...atom(
        'edts',
        atom('elst', [
          0,
          0,
          0,
          0,
          ...word(2),
          ...word(2000),
          ...word(0xffffffff),
          ...word(0x10000),
          ...word(20000),
          ...word(0),
          ...word(0x10000),
        ]),
      ),
    ...atom('mdia', [
      ...atom('mdhd', mdhd),
      ...atom('hdlr', hdlr),
      ...atom('minf', tables),
    ]),
  ]);
  final mvhd = Uint8List(100);
  mvhd.setRange(12, 16, word(1000));
  return (
    moov: atom('moov', [...atom('mvhd', mvhd), ...audio, ...text]),
    data: data,
  );
}
