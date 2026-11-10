import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../models/listening_journal.dart';

enum JournalReportFormat {
  csv('csv', 'text/csv', 'CSV'),
  json('json', 'application/json', 'JSON');

  final String extension;
  final String mimeType;
  final String label;

  const JournalReportFormat(this.extension, this.mimeType, this.label);
}

/// The same immutable scope used to capture a complete journal snapshot.
/// Human-readable filter descriptions deliberately stay out of report data.
class JournalReportFilters {
  final String? bookId;
  final int? fromUtcMs;
  final int? beforeUtcMs;
  final JournalPassageFilter? passage;

  const JournalReportFilters({
    this.bookId,
    this.fromUtcMs,
    this.beforeUtcMs,
    this.passage,
  });

  Map<String, Object?> toJson({required bool includeFilePaths}) => {
    'bookId': bookId ?? passage?.bookId,
    'fromUtcMs': fromUtcMs,
    'beforeUtcMs': beforeUtcMs,
    'passage': passage == null
        ? null
        : {
            'bookId': passage!.bookId,
            'fileRef': ListeningJournalReport.fileRef(
              passage!.bookId,
              passage!.filePath,
            ),
            if (includeFilePaths) 'filePath': passage!.filePath,
            if (passage!.isPoint) 'positionMs': passage!.startMs,
            if (!passage!.isPoint) 'startMs': passage!.startMs,
            if (!passage!.isPoint) 'endMs': passage!.endMs,
          },
  };
}

class JournalReportRequest {
  final JournalReportFormat format;
  final bool includeFilePaths;
  final JournalReportFilters filters;

  const JournalReportRequest({
    required this.format,
    this.includeFilePaths = false,
    this.filters = const JournalReportFilters(),
  });
}

/// A readable report, deliberately distinct from the restorable library format.
///
/// The caller captures all matching rows once, with the player's pending journal
/// evidence flushed. Encoding runs afterwards, outside the playback command and
/// database snapshot. Output is streamed in bounded chunks instead of building
/// a second full-history JSON string in memory.
class ListeningJournalReport {
  static const formatName = 'crisperplayer.listening-journal-report';
  static const formatVersion = 1;
  static const _chunkCharacters = 64 * 1024;

  final List<ListeningJournalEntry> entries;
  final JournalReportFilters filters;
  final DateTime exportedAtUtc;

  ListeningJournalReport({
    required List<ListeningJournalEntry> entries,
    required DateTime exportedAtUtc,
    this.filters = const JournalReportFilters(),
  }) : entries = List.unmodifiable(entries),
       exportedAtUtc = exportedAtUtc.toUtc();

  /// Stable, opaque track identity lets reports relate repeated plays and jumps
  /// without writing a physical path. This is a reference, not anonymization.
  static String fileRef(String bookId, String path) => const Uuid().v5(
    Namespace.url.value,
    'crisperplayer:journal-file:${jsonEncode([bookId, path])}',
  );

  Stream<List<int>> bytes({
    required JournalReportFormat format,
    bool includeFilePaths = false,
  }) => Stream<String>.fromIterable(
    chunks(format: format, includeFilePaths: includeFilePaths),
  ).transform(utf8.encoder);

  Iterable<String> chunks({
    required JournalReportFormat format,
    bool includeFilePaths = false,
  }) sync* {
    final pieces = switch (format) {
      JournalReportFormat.csv => _csv(includeFilePaths),
      JournalReportFormat.json => _json(includeFilePaths),
    };
    var buffer = StringBuffer();
    for (final piece in pieces) {
      buffer.write(piece);
      if (buffer.length >= _chunkCharacters) {
        yield buffer.toString();
        buffer = StringBuffer();
      }
    }
    if (buffer.isNotEmpty) yield buffer.toString();
  }

  Iterable<String> _json(bool includeFilePaths) sync* {
    final metadata = {
      'format': formatName,
      'version': formatVersion,
      'restorable': false,
      'exportedAtUtc': exportedAtUtc.toIso8601String(),
      'recordCount': entries.length,
      'includesFilePaths': includeFilePaths,
      'filters': filters.toJson(includeFilePaths: includeFilePaths),
    };
    final header = const JsonEncoder.withIndent('  ').convert(metadata);
    yield '${header.substring(0, header.length - 2)},\n  "entries": [';
    for (var i = 0; i < entries.length; i++) {
      yield '${i == 0 ? '\n' : ',\n'}    '
          '${jsonEncode(_record(entries[i], includeFilePaths))}';
    }
    yield '${entries.isEmpty ? '' : '\n  '}]\n}\n';
  }

  Map<String, Object?> _record(
    ListeningJournalEntry entry,
    bool includeFilePaths,
  ) => {
    'id': entry.id,
    'bookId': entry.bookId,
    'kind': entry.kind,
    'bookTitle': entry.bookTitle,
    'chapterTitle': entry.chapterTitle,
    'fileRef': fileRef(entry.bookId, entry.filePath),
    if (includeFilePaths) 'filePath': entry.filePath,
    'startMs': entry.startMs,
    'endMs': entry.endMs,
    'targetFileRef': entry.targetFilePath == null
        ? null
        : fileRef(entry.bookId, entry.targetFilePath!),
    if (includeFilePaths) 'targetFilePath': entry.targetFilePath,
    'targetPositionMs': entry.targetPositionMs,
    'startedAtMs': entry.startedAtMs,
    'endedAtMs': entry.endedAtMs,
    'startedAtUtc': _utc(entry.startedAtMs),
    'endedAtUtc': _utc(entry.endedAtMs),
    'utcOffsetMinutes': entry.utcOffsetMinutes,
    'speed': entry.speed,
    'reason': entry.reason,
  };

  Iterable<String> _csv(bool includeFilePaths) sync* {
    final columns = [
      'id',
      'bookId',
      'kind',
      'bookTitle',
      'chapterTitle',
      'fileRef',
      if (includeFilePaths) 'filePath',
      'startMs',
      'endMs',
      'targetFileRef',
      if (includeFilePaths) 'targetFilePath',
      'targetPositionMs',
      'startedAtMs',
      'endedAtMs',
      'startedAtUtc',
      'endedAtUtc',
      'utcOffsetMinutes',
      'speed',
      'reason',
    ];
    yield '${columns.map(_csvCell).join(',')}\r\n';
    for (final entry in entries) {
      final record = _record(entry, includeFilePaths);
      yield '${columns.map((key) => _csvCell(record[key])).join(',')}\r\n';
    }
  }

  static String _utc(int milliseconds) => DateTime.fromMillisecondsSinceEpoch(
    milliseconds,
    isUtc: true,
  ).toIso8601String();

  static final _leadingControls = RegExp(r'^[\s\x00-\x1f\x7f]+');
  static final _formulaStart = RegExp(r'^[=+\-@]');

  static String _csvCell(Object? value) {
    if (value == null) return '';
    // Only schema-defined numeric fields take this path. Negative UTC offsets
    // must remain numbers; untrusted text gets spreadsheet formula protection.
    if (value is num) return value.toString();
    var text = value.toString();
    final candidate = text.replaceFirst(_leadingControls, '');
    if (_formulaStart.hasMatch(candidate) ||
        (text.isNotEmpty && text.codeUnitAt(0) < 32)) {
      text = "'$text";
    }
    return '"${text.replaceAll('"', '""')}"';
  }
}
