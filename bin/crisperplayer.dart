import 'dart:convert';
import 'dart:io';
import 'package:crisperplayer/cli/control_client.dart';

const usage = '''CrisperPlayer desktop CLI
Usage: dart run bin/crisperplayer.dart [--control-file PATH] COMMAND [ARG]

  status                 Show playback state
  list [--query TEXT] [--sort FIELD] [--filter all|recent|finished]
  import FILE...         Import files or folders as one multi-track book
  chapters [BOOK_ID]      List chapters
  refresh-chapters [BOOK_ID]  Re-read embedded chapters without re-importing
  chapter INDEX [BOOK_ID] Seek to a chapter (numbered from 1)
  next-chapter / previous-chapter  Navigate chapters (previous restarts first)
  next / previous        Change physical track
  skip SECONDS           Skip forward or backward
  stop                   Stop playback
  sleep SECONDS [--chapter-end] / sleep cancel
  settings [KEY VALUE]   Show settings or set a JSON value
  history [BOOK_ID]      Show listening history
  bookmark-go ID / bookmark-delete ID
  bookmark-edit ID TITLE [NOTE]
  export FILE / restore FILE    Export or restore library metadata JSON
  clear-history --yes / clear-bookmarks --yes
  call COMMAND JSON      Structured access to every CLI operation
  delete BOOK_ID         Delete a book and its managed audio copies
  play [BOOK_ID]         Play a book or resume the loaded book
  load BOOK_ID           Load a book paused
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
        String? option(String name) {
          final index = args.indexOf(name);
          if (index < 0) return null;
          if (index + 1 >= args.length) {
            throw FormatException('$name requires a value');
          }
          args.removeAt(index);
          return args.removeAt(index);
        }
        final title = option('--title');
        final author = option('--author');
        if (args.isEmpty) {
          throw const FormatException('import requires files or folders');
        }
        final files = <File>[];
        const extensions = [
          'm4b',
          'm4a',
          'mp3',
          'flac',
          'ogg',
          'wav',
          'aac',
          'opus',
          'wma',
          'aiff',
          'aif',
          'mp2',
          'mov',
          'webm',
          '3gp',
          'mkv',
          'mka',
        ];
        for (final path in args) {
          final directory = Directory(path);
          if (await directory.exists()) {
            await for (final entry in directory.list(
              recursive: true,
              followLinks: false,
            )) {
              if (entry is File &&
                  extensions.contains(
                    entry.path.split('.').last.toLowerCase(),
                  )) {
                files.add(entry.absolute);
              }
            }
          } else {
            files.add(File(path).absolute);
          }
        }
        result = await client.importFiles(files, title: title, author: author);
      case 'list':
        final options = <String, Object?>{};
        while (args.isNotEmpty) {
          final flag = args.removeAt(0);
          if (!['--query', '--sort', '--filter'].contains(flag) ||
              args.isEmpty) {
            throw const FormatException(
              'list accepts --query, --sort, and --filter with values',
            );
          }
          options[flag.substring(2)] = args.removeAt(0);
        }
        result = await client.command(command, options);
      case 'status' ||
          'pause' ||
          'stop' ||
          'next' ||
          'previous' ||
          'next-chapter' ||
          'previous-chapter':
        if (args.isNotEmpty) {
          throw FormatException('$command takes no arguments');
        }
        result = await client.command(command);
      case 'delete' || 'load':
        if (args.length != 1) {
          throw FormatException('$command requires one book ID');
        }
        result = await client.command(command, {'bookId': args.single});
      case 'play' ||
          'bookmarks' ||
          'chapters' ||
          'history' ||
          'refresh-chapters':
        if (args.length > 1) {
          throw FormatException('$command accepts one book ID');
        }
        result = await client.command(command, {
          if (args.isNotEmpty) 'bookId': args.single,
        });
      case 'seek' || 'speed' || 'volume' || 'skip':
        if (args.length != 1) {
          throw FormatException('$command requires one number');
        }
        final number = double.tryParse(args.single);
        if (number == null || !number.isFinite) {
          throw const FormatException('Expected a finite number');
        }
        result = await client.command(command, {
          command == 'seek' || command == 'skip' ? 'seconds' : 'value': number,
        });
      case 'chapter':
        if (args.isEmpty || args.length > 2) {
          throw const FormatException(
            'chapter requires INDEX and optional BOOK_ID',
          );
        }
        final index = int.tryParse(args.first);
        if (index == null || index < 1) {
          throw const FormatException(
            'Chapter index must be a positive integer',
          );
        }
        result = await client.command(command, {
          'index': index,
          if (args.length == 2) 'bookId': args[1],
        });
      case 'sleep':
        if (args.length == 1 && args.single == 'cancel') {
          result = await client.command(command, {'cancel': true});
        } else {
          final end = args.remove('--chapter-end');
          if (args.length != 1) {
            throw const FormatException(
              'sleep requires SECONDS [--chapter-end] or cancel',
            );
          }
          final seconds = double.tryParse(args.single);
          if (seconds == null || !seconds.isFinite) {
            throw const FormatException('Invalid sleep duration');
          }
          result = await client.command(command, {
            'seconds': seconds,
            'endOfChapter': end,
          });
        }
      case 'settings':
        if (args.isEmpty) {
          result = await client.command(command);
        } else {
          if (args.length != 2) {
            throw const FormatException('settings requires KEY VALUE');
          }
          Object? value;
          try {
            value = jsonDecode(args[1]);
          } on FormatException {
            value = args[1];
          }
          result = await client.command(command, {
            'key': args.first,
            'value': value,
          });
        }
      case 'bookmark-go' || 'bookmark-delete':
        if (args.length != 1) throw FormatException('$command requires ID');
        result = await client.command(command, {'id': args.single});
      case 'bookmark-edit':
        if (args.length < 2 || args.length > 3) {
          throw const FormatException('bookmark-edit requires ID TITLE [NOTE]');
        }
        result = await client.command(command, {
          'id': args[0],
          'title': args[1],
          if (args.length == 3) 'note': args[2],
        });
      case 'clear-history' || 'clear-bookmarks':
        if (args.length != 1 || args.single != '--yes') {
          throw FormatException('$command requires --yes');
        }
        result = await client.command(command, {'confirm': true});
      case 'export' || 'restore':
        if (args.length != 1) throw FormatException('$command requires FILE');
        final file = File(args.single);
        if (command == 'export') {
          final data = await client.command(command);
          await file.writeAsString(
            const JsonEncoder.withIndent('  ').convert(data),
          );
          result = {'exported': file.absolute.path};
        } else {
          final data = jsonDecode(await file.readAsString());
          result = await client.command(command, {'data': data});
        }
      case 'call':
        if (args.length != 2) {
          throw const FormatException('call requires COMMAND JSON_OBJECT');
        }
        final data = jsonDecode(args[1]);
        if (data is! Map<String, dynamic>) {
          throw const FormatException('Expected a JSON object');
        }
        result = await client.command(args[0], data);
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
