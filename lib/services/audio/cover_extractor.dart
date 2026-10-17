import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;

/// Extracts embedded cover art from MP4/M4B/M4A files.
///
/// Supports `moov.udta.meta.ilst.covr` with `data` children (JPEG/PNG/GIF/BMP).
/// No FFI – pure Dart atom parsing, mirroring [ChapterParser] logic but
/// focused on `covr`.
class CoverExtractor {
  /// Try to extract cover to a temp file. Returns absolute path or null.
  /// Writes as `<tmp>/<basename>_cover.<ext>` (jpg/png).
  static Future<String?> extractCover(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return null;
    try {
      final bytes = await file.readAsBytes();
      if (bytes.length < 16) return null;
      final imageData = _parseBytes(bytes);
      if (imageData == null || imageData.isEmpty) return null;
      return await _writeTemp(filePath, imageData);
    } catch (_) {
      return null;
    }
  }

  /// Synchronous version returning raw image bytes (for testing).
  static Uint8List? extractBytes(Uint8List bytes) => _parseBytes(bytes);

  /// Build synthetic MP4 with a covr atom for testing.
  static Uint8List buildSyntheticMp4(Uint8List imageBytes, {int dataType = 13}) {
    // dataType 13 = JPEG, 14 = PNG
    final dataPayload = _buildDataPayload(imageBytes, dataType: dataType);
    final dataAtom = _atom('data', dataPayload);
    final covrAtom = _atom('covr', dataAtom);
    final ilstAtom = _atom('ilst', covrAtom);
    // meta requires 4 extra bytes + hdlr + ilst
    final hdlrPayload = Uint8List.fromList([
      0x00, 0x00, 0x00, 0x00, // version+flags
      0x00, 0x00, 0x00, 0x00, // pre_defined
      0x6d, 0x64, 0x69, 0x72, // mdir
      0x61, 0x70, 0x70, 0x6c, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    ]);
    final hdlrAtom = _atom('hdlr', hdlrPayload);
    final metaPayload = Uint8List.fromList([
      0x00, 0x00, 0x00, 0x00, // version+flags for meta
      ...hdlrAtom,
      ...ilstAtom,
    ]);
    final metaAtom = _atom('meta', metaPayload);
    final udtaAtom = _atom('udta', metaAtom);
    final moovAtom = _atom('moov', udtaAtom);
    final ftypPayload = Uint8List.fromList([
      0x4d, 0x34, 0x41, 0x20,
      0x00, 0x00, 0x02, 0x00, 0x4d, 0x34, 0x41, 0x20, 0x69, 0x73, 0x6f, 0x6d,
    ]);
    final ftypAtom = _atom('ftyp', ftypPayload);
    final mdatAtom = _atom('mdat', Uint8List.fromList([0x00]));
    return Uint8List.fromList([...ftypAtom, ...mdatAtom, ...moovAtom]);
  }

  // ---------------------------------------------------------------------------

  static Uint8List? _parseBytes(Uint8List bytes) {
    final atoms = _scanAtoms(bytes, 0, bytes.length);
    final moov = _findAtom(atoms, 'moov', bytes);
    if (moov == null) return null;
    // Search for covr anywhere under moov (usually moov.udta.meta.ilst.covr)
    final covr = _findRecursive(moov, 'covr', bytes);
    if (covr == null) return null;
    final covrPayload = _payload(covr, bytes);
    if (covrPayload.isEmpty) return null;
    // covr payload is a run of data atoms
    final children = _scanAtoms(covrPayload, 0, covrPayload.length);
    for (final child in children) {
      if (child.type != 'data') continue;
      final dataBytes = _payloadForData(child, covrPayload);
      if (dataBytes != null && dataBytes.isNotEmpty) return dataBytes;
    }
    // Fallback: try scanning covr bytes reinterpreted (in case _scan failed)
    return null;
  }

  static Uint8List? _payloadForData(_Atom dataAtom, Uint8List covrPayload) {
    // data atom payload layout in Go: 4 typeFlags + 4 locale/header pad then image
    // But we stored payload as header->dataStart..offset+size. So _payload already
    // gives the inner bytes after header (8). Inside those inner bytes, first 8
    // are type(4) then 4 reserved/locale, then image.
    // So we need to look inside the dataAtom's payload (already extracted via _payload)
    // But _payload currently returns bytes from dataAtom.dataStart..end inside covrPayload.
    // That is the inner of data atom: includes type+pad+image.
    // So skip first 8 bytes.
    final inner = _payloadDataAtomInner(dataAtom, covrPayload);
    if (inner == null) return null;
    // inner is type+reserved+image; image starts at 8
    if (inner.length <= 8) return null;
    return inner.sublist(8);
  }

  static Uint8List? _payloadDataAtomInner(_Atom atom, Uint8List containerBytes) {
    final end = atom.offset + atom.size;
    final start = atom.dataStart;
    if (start >= end) return null;
    final s = start.clamp(0, containerBytes.length);
    final e = end.clamp(0, containerBytes.length);
    return containerBytes.sublist(s, e);
  }

  static Uint8List _buildDataPayload(Uint8List imageBytes, {int dataType = 13}) {
    // data payload: 4 typeFlags (?) where low 24 bits = type, then 4 locale=0, then image
    // Use 16 bytes before image: 4 type(1 byte type in low?), 4+8 as in Go expects
    // Go parseDataAtoms expects: at pos+8: 4 bytes type where low 24 bits is type, pos+12: 4 bytes locale?
    // Actually it reads body[pos+8:pos+12] & 0x00FFFFFF for type, and body[pos+16:pos+length] is Data.
    // So data atom body = 4 typeFlags + 4 ?? + 8 ??? Wait Go offset 16 means: header 8 + 4 type+flags? Let's match:
    // In Go parseDataAtoms: body[pos+8:pos+12] is typeFlags, values = body[pos+16:pos+length]
    // So inside data atom's body (after header 8), layout is: 4 bytes typeFlags, 4 bytes ?,
    // then image starts at 8 bytes after body start? Actually 16 from pos means 8 header +8 extra.
    // So we need to emit 8 bytes padding before image: first 4 are type, next 4 are reserved.
    final out = Uint8List(8 + imageBytes.length);
    // type in last byte of first 4? Use BE uint32 where low 24 bits = type
    // For simplicity put 0x00 0x00 0x00 type
    out[3] = dataType;
    // next 4 bytes 0
    for (int i = 0; i < imageBytes.length; i++) out[8 + i] = imageBytes[i];
    return out;
  }

  static Future<String> _writeTemp(String originalPath, Uint8List imageData) async {
    final ext = _extForImage(imageData);
    final base = p.basenameWithoutExtension(originalPath);
    String tmpDir;
    try {
      // Try to get temp from system; path_provider would need Flutter binding.
      // Use system temp.
      tmpDir = Directory.systemTemp.path;
      // Ensure subdir
      final sub = Directory(p.join(tmpDir, 'crisper_covers'));
      if (!await sub.exists()) await sub.create(recursive: true);
      tmpDir = sub.path;
    } catch (_) {
      tmpDir = Directory.systemTemp.path;
    }
    final outPath = p.join(tmpDir, '${base}_cover$ext');
    final outFile = File(outPath);
    await outFile.writeAsBytes(imageData);
    return outFile.path;
  }

  static String _extForImage(Uint8List data) {
    if (data.length >= 3 && data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF) return '.jpg';
    if (data.length >= 4 && data[0] == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47) return '.png';
    if (data.length >= 4 && data[0] == 0x47 && data[1] == 0x49 && data[2] == 0x46) return '.gif';
    if (data.length >= 2 && data[0] == 0x42 && data[1] == 0x4D) return '.bmp';
    return '.jpg';
  }

  // -- Atom helpers (mirrored from chapter_parser) ---------------------------

  static _Atom? _findAtom(List<_Atom> atoms, String type, Uint8List bytes) {
    for (final a in atoms) if (a.type == type) return a;
    return null;
  }

  static _Atom? _findRecursive(_Atom root, String type, Uint8List bytes) {
    if (root.type == type) return root;
    final children = _childrenOf(root, bytes);
    for (final c in children) {
      if (c.type == type) return c;
      final deep = _findRecursive(c, type, bytes);
      if (deep != null) return deep;
    }
    return null;
  }

  static List<_Atom> _childrenOf(_Atom parent, Uint8List bytes) {
    int start = parent.dataStart;
    int end = parent.offset + parent.size;
    if (parent.type == 'meta') {
      if (start + 4 <= end) start += 4;
    }
    return _scanAtoms(bytes, start, end);
  }

  static List<_Atom> _scanAtoms(Uint8List bytes, int start, int end) {
    final out = <_Atom>[];
    int pos = start;
    while (pos + 8 <= end) {
      final size = _u32BE(bytes, pos);
      final type = _typeStr(bytes, pos + 4);
      int headerSize = 8;
      int atomSize = size;
      if (size == 1) {
        if (pos + 16 > end) break;
        atomSize = _u64BE(bytes, pos + 8).toInt();
        headerSize = 16;
      } else if (size == 0) {
        atomSize = end - pos;
      }
      if (atomSize < headerSize || atomSize == 0) break;
      if (pos + atomSize > end) {
        if (type == 'mdat' || type == 'moov' || type == 'udta' || type == 'meta' || type == 'ilst' || type == 'covr') {
          atomSize = end - pos;
        } else {
          break;
        }
      }
      out.add(_Atom(type: type, offset: pos, size: atomSize, headerSize: headerSize, dataStart: pos + headerSize));
      pos += atomSize;
    }
    return out;
  }

  static Uint8List _payload(_Atom atom, Uint8List bytes) {
    final end = atom.offset + atom.size;
    final start = atom.dataStart;
    if (start >= end) return Uint8List(0);
    final s = start.clamp(0, bytes.length);
    final e = end.clamp(0, bytes.length);
    return bytes.sublist(s, e);
  }

  static int _u32BE(Uint8List b, int off) => (b[off] << 24) | (b[off + 1] << 16) | (b[off + 2] << 8) | b[off + 3];
  static int _u64BE(Uint8List b, int off) {
    final hi = _u32BE(b, off);
    final lo = _u32BE(b, off + 4);
    return (hi * 0x100000000) + lo;
  }

  static String _typeStr(Uint8List b, int off) => String.fromCharCodes([b[off], b[off + 1], b[off + 2], b[off + 3]]);

  static Uint8List _atom(String type, Uint8List payload) {
    final size = 8 + payload.length;
    final out = Uint8List(size);
    out[0] = (size >> 24) & 0xFF;
    out[1] = (size >> 16) & 0xFF;
    out[2] = (size >> 8) & 0xFF;
    out[3] = size & 0xFF;
    final codes = type.codeUnits;
    for (int i = 0; i < 4; i++) out[4 + i] = codes[i];
    for (int i = 0; i < payload.length; i++) out[8 + i] = payload[i];
    return out;
  }
}

class _Atom {
  final String type;
  final int offset;
  final int size;
  final int headerSize;
  final int dataStart;
  _Atom({required this.type, required this.offset, required this.size, required this.headerSize, required this.dataStart});
}
