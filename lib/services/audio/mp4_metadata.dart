import 'dart:io';
import 'dart:typed_data';

/// Read only the movie metadata atom. Large audio payloads are skipped by seek,
/// so importing a multi-gigabyte M4B never loads its audio into Dart memory.
Future<Uint8List> readMp4Metadata(File file) async {
  final input = await file.open();
  try {
    final length = await input.length();
    var offset = 0;
    while (offset + 8 <= length) {
      await input.setPosition(offset);
      final header = await input.read(8);
      if (header.length != 8) break;
      var size = ByteData.sublistView(header).getUint32(0);
      var headerSize = 8;
      if (size == 1) {
        final extended = await input.read(8);
        if (extended.length != 8) break;
        size = ByteData.sublistView(extended).getUint64(0);
        headerSize = 16;
      } else if (size == 0) {
        size = length - offset;
      }
      if (size < headerSize || size > length - offset) break;
      if (String.fromCharCodes(header.sublist(4, 8)) == 'moov') {
        if (size > 32 * 1024 * 1024) {
          throw const FormatException('MP4 metadata exceeds 32 MB');
        }
        await input.setPosition(offset);
        final bytes = await input.read(size);
        if (bytes.length == size) return bytes;
        break;
      }
      offset += size;
    }
    return Uint8List(0);
  } finally {
    await input.close();
  }
}
