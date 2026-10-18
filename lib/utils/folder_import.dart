import 'dart:io';
import 'package:path/path.dart' as p;

/// A reviewable import plan. Scanning never copies or changes source files.
class FolderBook {
  final String folder;
  final List<String> files;
  String get title => p.basename(folder);
  FolderBook(this.folder, Iterable<String> files)
    : files = List.unmodifiable(files.toList()..sort(naturalPathCompare));

  Map<String, Object> toJson() => {
    'folder': folder,
    'title': title,
    'files': files,
  };
}

const audioExtensions = {
  '.m4b',
  '.m4a',
  '.mp3',
  '.flac',
  '.ogg',
  '.wav',
  '.aac',
  '.opus',
  '.wma',
  '.aiff',
  '.aif',
  '.mp2',
  '.mov',
  '.webm',
  '.3gp',
  '.mkv',
  '.mka',
};

int naturalPathCompare(String a, String b) {
  final pattern = RegExp(r'\d+|\D+');
  final aa = pattern.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final bb = pattern.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < aa.length && i < bb.length; i++) {
    final an = BigInt.tryParse(aa[i]);
    final bn = BigInt.tryParse(bb[i]);
    final comparison = an != null && bn != null
        ? an.compareTo(bn)
        : aa[i].compareTo(bb[i]);
    if (comparison != 0) return comparison;
  }
  final length = aa.length.compareTo(bb.length);
  return length != 0 ? length : a.compareTo(b);
}

/// One book per directory containing audio, at any depth. Numbered disc/part
/// directories belong to their parent book. Other nested books stay separate.
/// Links and hidden directories/files are omitted, including macOS ._ files.
Future<List<FolderBook>> scanBookFolders(String path) async {
  final root = Directory(p.normalize(p.absolute(path)));
  if (!await root.exists()) {
    throw FileSystemException('Library folder is unavailable', path);
  }
  final grouped = <String, List<String>>{};
  final disc = RegExp(r'^(cd|disc|disk|part)[ _.-]*\d+$', caseSensitive: false);
  Future<void> visit(Directory directory) async {
    await for (final entry in directory.list(followLinks: false)) {
      if (p.basename(entry.path).startsWith('.')) continue;
      if (entry is Directory) {
        await visit(entry);
      } else if (entry is File &&
          audioExtensions.contains(p.extension(entry.path).toLowerCase())) {
        var folder = directory.path;
        if (folder != root.path && disc.hasMatch(p.basename(folder))) {
          folder = p.dirname(folder);
        }
        grouped.putIfAbsent(folder, () => []).add(entry.path);
      }
    }
  }

  await visit(root);
  final folders = grouped.keys.toList()..sort(naturalPathCompare);
  return [for (final folder in folders) FolderBook(folder, grouped[folder]!)];
}
