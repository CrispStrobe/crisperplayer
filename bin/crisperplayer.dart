import 'dart:convert';
import 'dart:io';
import 'package:crisperplayer/cli/control_client.dart';

const usage = '''CrisperPlayer desktop CLI
Usage: dart run bin/crisperplayer.dart [--control-file PATH] COMMAND [ARG]

  status                 Show playback state
  list                   List library books and IDs
  import FILE            Copy one audio file into the library
  delete BOOK_ID         Delete a book and its managed audio copies
  play [BOOK_ID]         Play a book or resume the loaded book
  pause                  Pause and save progress
  seek SECONDS           Seek from the start of the whole book
  speed NUMBER           Set playback speed (0.5–3.0)
  volume NUMBER          Set volume (0–1)
  bookmark [TITLE]       Bookmark the current position
  bookmarks [BOOK_ID]    List bookmarks

The desktop app must be running with CLI enabled. Output is JSON.
''';

Future<void> main(List<String> arguments) async {
  final args = List<String>.of(arguments);
  if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
    stdout.write(usage);
    return;
  }
  try {
    var descriptor = ControlClient.defaultDescriptor();
    if (args.first == '--control-file') {
      if (args.length < 3) {
        throw const FormatException('--control-file requires PATH and COMMAND');
      }
      args.removeAt(0);
      descriptor = File(args.removeAt(0));
    }
    final command = args.removeAt(0);
    final client = ControlClient(descriptor);
    Object? result;
    switch (command) {
      case 'import':
        if (args.length != 1) {
          throw const FormatException('import requires one audio file');
        }
        result = await client.importFile(File(args.single).absolute);
      case 'status' || 'list' || 'pause':
        if (args.isNotEmpty) {
          throw FormatException('$command takes no arguments');
        }
        result = await client.command(command);
      case 'delete':
        if (args.length != 1) {
          throw const FormatException('delete requires one book ID');
        }
        result = await client.command(command, {'bookId': args.single});
      case 'play' || 'bookmarks':
        if (args.length > 1) {
          throw FormatException('$command accepts one book ID');
        }
        result = await client.command(command, {
          if (args.isNotEmpty) 'bookId': args.single,
        });
      case 'seek' || 'speed' || 'volume':
        if (args.length != 1) {
          throw FormatException('$command requires one number');
        }
        final number = double.tryParse(args.single);
        if (number == null || !number.isFinite) {
          throw const FormatException('Expected a finite number');
        }
        result = await client.command(command, {
          command == 'seek' ? 'seconds' : 'value': number,
        });
      case 'bookmark':
        result = await client.command(command, {
          if (args.isNotEmpty) 'title': args.join(' '),
        });
      default:
        throw FormatException('Unknown command: $command. Use --help.');
    }
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
  } catch (error) {
    stderr.writeln('crisperplayer: $error');
    exitCode = 1;
  }
}
