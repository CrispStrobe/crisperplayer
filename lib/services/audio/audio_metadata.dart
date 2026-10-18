import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'cover_extractor.dart';
import 'mp4_metadata.dart';

class AudioMetadata {
  final String? title;
  final String? author;
  final Uint8List? artwork;
  const AudioMetadata({this.title, this.author, this.artwork});

  /// Read tag data only. Never read an entire audiobook to discover metadata.
  static Future<AudioMetadata> read(String path) async {
    final input = await File(path).open();
    try {
      final header = await input.read(10);
      if (header.length == 10 &&
          ascii.decode(header.sublist(0, 3), allowInvalid: true) == 'ID3') {
        final size = _syncSafe(header, 6);
        if (size < 0 || size > 16 * 1024 * 1024) return const AudioMetadata();
        final body = await input.read(size);
        if (body.length != size) return const AudioMetadata();
        return id3(Uint8List.fromList([...header, ...body]));
      }
    } finally {
      await input.close();
    }
    if (!RegExp(r'\.(m4a|m4b|mp4|mov)$', caseSensitive: false).hasMatch(path)) {
      return const AudioMetadata();
    }
    try {
      return mp4(await readMp4Metadata(File(path)));
    } on FormatException {
      return const AudioMetadata();
    }
  }

  static AudioMetadata mp4(Uint8List bytes) {
    final tags = <String, String>{};
    void visit(int start, int end, int depth) {
      if (depth > 8) return;
      for (var p = start; p + 8 <= end;) {
        var size = _uint32(bytes, p);
        final type = latin1.decode(bytes.sublist(p + 4, p + 8));
        var header = 8;
        if (size == 1) {
          if (p + 16 > end) return;
          size = ByteData.sublistView(bytes).getUint64(p + 8);
          header = 16;
        } else if (size == 0) {
          size = end - p;
        }
        if (size < header || size > end - p) return;
        final payload = p + header;
        if ({'moov', 'udta', 'meta', 'ilst'}.contains(type)) {
          visit(payload + (type == 'meta' ? 4 : 0), p + size, depth + 1);
        } else if ({'©nam', '©alb', '©ART', 'aART', '©wrt'}.contains(type)) {
          // Metadata item -> data atom -> type/locale (eight bytes) -> text.
          var q = payload;
          while (q + 16 <= p + size) {
            final n = _uint32(bytes, q);
            if (n < 16 || q + n > p + size) break;
            if (latin1.decode(bytes.sublist(q + 4, q + 8)) == 'data' &&
                (_uint32(bytes, q + 8) & 0xffffff) == 1) {
              final value = _clean(
                utf8.decode(bytes.sublist(q + 16, q + n), allowMalformed: true),
              );
              if (value != null) tags[type] = value;
            }
            q += n;
          }
        }
        p += size;
      }
    }

    visit(0, bytes.length, 0);
    return AudioMetadata(
      title: tags['©alb'] ?? tags['©nam'],
      author: tags['©ART'] ?? tags['aART'] ?? tags['©wrt'],
      artwork: CoverExtractor.extractBytes(bytes),
    );
  }

  /// ID3v2.3 and 2.4 text/APIC frames, with UTF-16 and unsynchronisation.
  static AudioMetadata id3(Uint8List bytes) {
    if (bytes.length < 10 ||
        latin1.decode(bytes.sublist(0, 3)) != 'ID3' ||
        ![3, 4].contains(bytes[3])) {
      return const AudioMetadata();
    }
    final version = bytes[3];
    final length = _syncSafe(bytes, 6);
    if (length < 0 || length > 16 * 1024 * 1024 || length + 10 > bytes.length) {
      return const AudioMetadata();
    }
    var body = bytes.sublist(10, 10 + length);
    if (version == 3 && (bytes[5] & 0x80) != 0) body = _unsync(body);
    var p = 0;
    if ((bytes[5] & 0x40) != 0) {
      if (body.length < 4) return const AudioMetadata();
      p = version == 4 ? _syncSafe(body, 0) : _uint32(body, 0) + 4;
      if (p < 4 || p > body.length) return const AudioMetadata();
    }
    final tags = <String, String>{};
    Uint8List? artwork;
    var frontCover = false;
    while (p + 10 <= body.length) {
      final id = latin1.decode(body.sublist(p, p + 4));
      if (!RegExp(r'^[A-Z0-9]{4}$').hasMatch(id)) break;
      final size = version == 4 ? _syncSafe(body, p + 4) : _uint32(body, p + 4);
      final flags = body[p + 9];
      p += 10;
      if (size <= 0 || size > body.length - p) break;
      var data = body.sublist(p, p + size);
      p += size;
      // Compressed/encrypted frames require additional decoding; skip safely.
      if (version == 3 ? flags != 0 : (flags & 0xfc) != 0) continue;
      if (version == 4) {
        if ((flags & 2) != 0 || (bytes[5] & 0x80) != 0) data = _unsync(data);
        if ((flags & 1) != 0) {
          if (data.length < 4) continue;
          data = data.sublist(4);
        }
      }
      if (data.isEmpty) continue;
      if ({'TIT2', 'TALB', 'TPE1', 'TPE2', 'TCOM'}.contains(id)) {
        final value = _clean(_text(data.sublist(1), data.first));
        if (value != null) tags[id] = value;
      } else if (id == 'APIC' && data.length < 10 * 1024 * 1024) {
        final mimeEnd = data.indexOf(0, 1);
        if (mimeEnd < 0 || mimeEnd + 2 >= data.length) continue;
        final kind = data[mimeEnd + 1];
        final step = data[0] == 1 || data[0] == 2 ? 2 : 1;
        var end = mimeEnd + 2;
        while (end + step <= data.length) {
          if (data[end] == 0 && (step == 1 || data[end + 1] == 0)) break;
          end += step;
        }
        if (end + step > data.length) continue;
        final image = data.sublist(end + step);
        if (imageExtension(image) == null || (frontCover && kind != 3)) {
          continue;
        }
        artwork = image;
        frontCover = kind == 3;
      }
    }
    return AudioMetadata(
      title: tags['TALB'] ?? tags['TIT2'],
      author: tags['TPE1'] ?? tags['TPE2'] ?? tags['TCOM'],
      artwork: artwork,
    );
  }

  static String? imageExtension(List<int> data) {
    if (data.length >= 3 && data[0] == 255 && data[1] == 216 && data[2] == 255) {
      return 'jpg';
    }
    if (data.length >= 8 &&
        data.take(8).join(',') == '137,80,78,71,13,10,26,10') {
      return 'png';
    }
    return null;
  }

  static String? _clean(String value) {
    value = value.split('\u0000').first.trim();
    return value.isEmpty ? null : value;
  }

  static String _text(Uint8List data, int encoding) {
    if (encoding == 0) return latin1.decode(data);
    if (encoding == 3) return utf8.decode(data, allowMalformed: true);
    if (encoding != 1 && encoding != 2) return '';
    var start = 0;
    var endian = Endian.big;
    if (encoding == 1) {
      if (data.length < 2) return '';
      if (data[0] == 255 && data[1] == 254) {
        endian = Endian.little;
        start = 2;
      } else if (data[0] == 254 && data[1] == 255) {
        start = 2;
      } else {
        return '';
      }
    }
    final view = ByteData.sublistView(data);
    return String.fromCharCodes([
      for (var i = start; i + 2 <= data.length; i += 2)
        view.getUint16(i, endian),
    ]);
  }

  static int _uint32(Uint8List data, int p) =>
      ByteData.sublistView(data).getUint32(p);
  static int _syncSafe(Uint8List data, int p) {
    var result = 0;
    for (var i = p; i < p + 4; i++) {
      if (data[i] > 127) return -1;
      result = (result << 7) | data[i];
    }
    return result;
  }

  static Uint8List _unsync(Uint8List data) => Uint8List.fromList([
    for (var i = 0; i < data.length; i++)
      if (!(i > 0 && data[i] == 0 && data[i - 1] == 255)) data[i],
  ]);
}
