import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Bounded readers for FLAC metadata and Ogg Vorbis/Opus comment packets.
class VorbisMetadata {
  static const limit = 16 * 1024 * 1024;
  final Map<String, String> tags = {};
  Uint8List? artwork;
  bool _frontCover = false;

  static Future<VorbisMetadata> read(
    RandomAccessFile input, {
    required bool flac,
  }) async {
    final result = VorbisMetadata();
    await input.setPosition(0);
    try {
      if (flac) {
        await result._flac(input);
      } else {
        await result._ogg(input);
      }
    } on RangeError {
      // Damaged tags must not prevent otherwise playable audio from importing.
    } on FormatException {
      // Invalid base64/length fields are ignored, without unbounded allocation.
    }
    return result;
  }

  Future<void> _flac(RandomAccessFile input) async {
    if (!_starts(await input.read(4), 'fLaC')) return;
    var consumed = 4;
    for (var i = 0; i < 1024; i++) {
      final header = await input.read(4);
      if (header.length != 4) return;
      final size = (header[1] << 16) | (header[2] << 8) | header[3];
      final type = header[0] & 0x7f;
      consumed += 4 + size;
      if (consumed > limit) return;
      if (type == 4 || type == 6) {
        final bytes = await input.read(size);
        if (bytes.length != size) return;
        if (type == 4) {
          comments(bytes);
        } else {
          _picture(bytes);
        }
      } else {
        await input.setPosition(await input.position() + size);
      }
      if ((header[0] & 0x80) != 0) return;
    }
  }

  Future<void> _ogg(RandomAccessFile input) async {
    final pending = <int, BytesBuilder>{};
    final sequence = <int, int>{};
    int? audioSerial;
    var consumed = 0;
    var packets = 0;
    for (var page = 0; page < 1024; page++) {
      final header = await input.read(27);
      if (header.length != 27 || !_starts(header, 'OggS') || header[4] != 0) {
        return;
      }
      final fields = ByteData.sublistView(header);
      final serial = fields.getUint32(14, Endian.little);
      final number = fields.getUint32(18, Endian.little);
      final segments = await input.read(header[26]);
      if (segments.length != header[26]) return;
      final size = segments.fold<int>(0, (sum, value) => sum + value);
      consumed += 27 + segments.length + size;
      if (consumed > limit) return;
      final body = await input.read(size);
      if (body.length != size) return;
      if (audioSerial != null && serial != audioSerial) continue;
      if (pending.length >= 8 && !pending.containsKey(serial)) return;
      final packet = pending.putIfAbsent(
        serial,
        () => BytesBuilder(copy: false),
      );
      final continued = (header[5] & 1) != 0;
      if (continued != (packet.length > 0)) return;
      if (sequence.containsKey(serial) && sequence[serial]! + 1 != number) {
        return;
      }
      sequence[serial] = number;
      var offset = 0;
      for (final segment in segments) {
        packet.add(Uint8List.sublistView(body, offset, offset + segment));
        offset += segment;
        if (packet.length > limit) return;
        if (segment == 255) continue;
        final bytes = packet.takeBytes();
        if (++packets > 32) return;
        if (_starts(bytes, 'OpusHead') ||
            (bytes.length >= 7 &&
                bytes[0] == 1 &&
                _starts(bytes.sublist(1), 'vorbis'))) {
          audioSerial = serial;
        } else if (serial == audioSerial && _starts(bytes, 'OpusTags')) {
          comments(bytes.sublist(8));
          return;
        } else if (serial == audioSerial &&
            bytes.length >= 7 &&
            bytes[0] == 3 &&
            _starts(bytes.sublist(1), 'vorbis')) {
          comments(bytes.sublist(7));
          return;
        }
      }
    }
  }

  void comments(Uint8List bytes) {
    if (bytes.length < 8 || bytes.length > limit) return;
    final data = ByteData.sublistView(bytes);
    final vendor = data.getUint32(0, Endian.little);
    if (vendor > bytes.length - 8) return;
    var position = 4 + vendor;
    final count = data.getUint32(position, Endian.little);
    position += 4;
    if (count > 100000) return;
    for (var i = 0; i < count; i++) {
      if (position + 4 > bytes.length) return;
      final length = data.getUint32(position, Endian.little);
      position += 4;
      if (length > bytes.length - position) return;
      final text = utf8.decode(
        bytes.sublist(position, position + length),
        allowMalformed: true,
      );
      position += length;
      final split = text.indexOf('=');
      if (split <= 0) continue;
      final key = text.substring(0, split).toUpperCase();
      final value = text.substring(split + 1).trim();
      if (value.isEmpty) continue;
      if (key == 'METADATA_BLOCK_PICTURE') {
        try {
          _picture(base64Decode(value));
        } on FormatException {
          /* ignore this picture */
        }
      } else if (key == 'COVERART' && artwork == null) {
        try {
          _setImage(base64Decode(value), false);
        } on FormatException {
          /* ignore */
        }
      } else if (key == 'ARTIST' && tags.containsKey(key)) {
        tags[key] = '${tags[key]}, $value';
      } else {
        tags[key] = value;
      }
    }
  }

  void _picture(Uint8List bytes) {
    if (bytes.length < 32 || bytes.length > limit) return;
    final data = ByteData.sublistView(bytes);
    final kind = data.getUint32(0);
    final mimeLength = data.getUint32(4);
    if (mimeLength > bytes.length - 12) return;
    final description = 8 + mimeLength;
    final descriptionLength = data.getUint32(description);
    final dimensions = description + 4 + descriptionLength;
    if (dimensions + 20 > bytes.length) return;
    final size = data.getUint32(dimensions + 16);
    final start = dimensions + 20;
    if (size > bytes.length - start) return;
    _setImage(bytes.sublist(start, start + size), kind == 3);
  }

  void _setImage(Uint8List image, bool front) {
    final jpeg =
        image.length >= 3 &&
        image[0] == 255 &&
        image[1] == 216 &&
        image[2] == 255;
    final png =
        image.length >= 8 &&
        image.take(8).join(',') == '137,80,78,71,13,10,26,10';
    if ((!jpeg && !png) ||
        image.length > 10 * 1024 * 1024 ||
        (_frontCover && !front)) {
      return;
    }
    artwork = image;
    _frontCover = front;
  }

  List<({String title, Duration start})> get chapters {
    final result = <({String title, Duration start})>[];
    for (final entry in tags.entries) {
      final key = RegExp(r'^CHAPTER(\d{3,})$').firstMatch(entry.key);
      if (key == null) continue;
      final time = RegExp(
        r'^(\d+):([0-5]\d):([0-5]\d)(?:\.(\d{1,3}))?$',
      ).firstMatch(entry.value);
      if (time == null) continue;
      final millis = int.tryParse((time[4] ?? '').padRight(3, '0')) ?? 0;
      final hours = int.tryParse(time[1]!);
      if (hours == null || hours > 100000) continue;
      result.add((
        title: tags['${entry.key}NAME'] ?? 'Chapter ${int.parse(key[1]!)}',
        start: Duration(
          hours: hours,
          minutes: int.parse(time[2]!),
          seconds: int.parse(time[3]!),
          milliseconds: millis,
        ),
      ));
    }
    result.sort((a, b) => a.start.compareTo(b.start));
    return result;
  }

  static bool _starts(List<int> bytes, String text) =>
      bytes.length >= text.length &&
      String.fromCharCodes(bytes.take(text.length)) == text;
}
