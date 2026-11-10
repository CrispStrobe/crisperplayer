import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../models/listening_journal.dart';
import '../services/audio/playback_service.dart';
import '../services/listening_journal_report.dart';
import '../utils/platform_utils.dart';

class JournalReportExportResult {
  final String path;
  final int entryCount;
  final String? notice;

  const JournalReportExportResult({
    required this.path,
    required this.entryCount,
    this.notice,
  });
}

typedef JournalReportExporter =
    Future<JournalReportExportResult?> Function(JournalReportRequest request);

/// Captures the current filter scope before opening its options dialog.
/// The report always includes every matching entry, including unloaded pages.
class JournalExportButton extends StatefulWidget {
  final PlaybackService playback;
  final String? bookId;
  final int? fromUtcMs;
  final int? beforeUtcMs;
  final JournalPassageFilter? passage;
  final String? filterDescription;
  final bool enabled;

  /// Optional integration seam; the default writes a file and offers sharing on
  /// mobile. Returning null indicates cancellation without a created report.
  final JournalReportExporter? exporter;

  const JournalExportButton({
    super.key,
    required this.playback,
    this.bookId,
    this.fromUtcMs,
    this.beforeUtcMs,
    this.passage,
    this.filterDescription,
    this.enabled = true,
    this.exporter,
  });

  @override
  State<JournalExportButton> createState() => _JournalExportButtonState();
}

class _JournalExportButtonState extends State<JournalExportButton> {
  bool _busy = false;
  bool _writing = false;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    key: const ValueKey('journal-export-button'),
    onPressed: widget.enabled && !_busy ? _export : null,
    icon: _writing
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.file_download_outlined, size: 18),
    label: Text(_writing ? 'Exporting…' : 'Export report'),
  );

  Future<void> _export() async {
    final playback = widget.playback;
    final exporter = widget.exporter;
    final filters = JournalReportFilters(
      bookId: widget.bookId,
      fromUtcMs: widget.fromUtcMs,
      beforeUtcMs: widget.beforeUtcMs,
      passage: widget.passage,
    );
    final description = widget.filterDescription ?? 'Current journal filters';
    final renderBox = context.findRenderObject();
    final origin = renderBox is RenderBox && renderBox.hasSize
        ? renderBox.localToGlobal(Offset.zero) & renderBox.size
        : null;
    setState(() => _busy = true);
    try {
      final options = await showDialog<_ExportOptions>(
        context: context,
        builder: (context) => _ReportOptionsDialog(description: description),
      );
      if (options == null || !mounted) return;
      setState(() => _writing = true);
      final request = JournalReportRequest(
        format: options.format,
        includeFilePaths: options.includeFilePaths,
        filters: filters,
      );
      final result = exporter != null
          ? await exporter(request)
          : await _writeReport(playback, request, origin);
      if (!mounted || result == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: Text(
            'Saved ${result.entryCount} journal '
            '${result.entryCount == 1 ? 'entry' : 'entries'} to ${result.path}'
            '${result.notice == null ? '' : '\n${result.notice}'}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not export the journal report: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _writing = false;
        });
      }
    }
  }

  Future<JournalReportExportResult?> _writeReport(
    PlaybackService playback,
    JournalReportRequest request,
    Rect? origin,
  ) async {
    if (kIsWeb) {
      throw UnsupportedError('Journal report files require the installed app.');
    }
    // Ask for a desktop destination before capturing playback, so cancellation
    // does not create a report or hold a database snapshot open.
    final String directory;
    if (isDesktop) {
      final chosen = await FilePicker.getDirectoryPath(
        dialogTitle: 'Save journal report in this folder',
      );
      if (chosen == null) return null;
      directory = chosen;
    } else {
      directory = (await getApplicationDocumentsDirectory()).path;
    }

    final entries = await playback.listeningJournalSnapshot(
      bookId: request.filters.bookId,
      fromUtcMs: request.filters.fromUtcMs,
      beforeUtcMs: request.filters.beforeUtcMs,
      passage: request.filters.passage,
    );
    final report = ListeningJournalReport(
      entries: entries,
      exportedAtUtc: DateTime.now(),
      filters: request.filters,
    );
    final stamp = report.exportedAtUtc.toIso8601String().replaceAll(':', '-');
    final file = File(
      '$directory${Platform.pathSeparator}crisperplayer_journal_'
      '${stamp}_${const Uuid().v4().substring(0, 8)}.${request.format.extension}',
    );
    try {
      final sink = file.openWrite();
      try {
        await sink.addStream(
          report.bytes(
            format: request.format,
            includeFilePaths: request.includeFilePaths,
          ),
        );
        await sink.flush();
      } finally {
        await sink.close();
      }
    } catch (_) {
      // A partial file must never look like a complete listening record.
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Preserve the original write error if cleanup is also unavailable.
      }
      rethrow;
    }

    String? notice;
    if (isMobile && mounted) {
      try {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path, mimeType: request.format.mimeType)],
            title: 'Listening journal report',
            text: '${entries.length} CrisperPlayer journal entries',
            sharePositionOrigin: origin,
          ),
        );
      } catch (_) {
        notice = 'Sharing is unavailable. The report is saved on this device.';
      }
    }
    return JournalReportExportResult(
      path: file.path,
      entryCount: entries.length,
      notice: notice,
    );
  }
}

class _ExportOptions {
  final JournalReportFormat format;
  final bool includeFilePaths;

  const _ExportOptions(this.format, this.includeFilePaths);
}

class _ReportOptionsDialog extends StatefulWidget {
  final String description;

  const _ReportOptionsDialog({required this.description});

  @override
  State<_ReportOptionsDialog> createState() => _ReportOptionsDialogState();
}

class _ReportOptionsDialogState extends State<_ReportOptionsDialog> {
  JournalReportFormat _format = JournalReportFormat.csv;
  bool _includeFilePaths = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Export listening report'),
    scrollable: true,
    content: SizedBox(
      width: 360,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(widget.description),
          const SizedBox(height: 8),
          const Text(
            'Includes every matching entry, across all journal pages.',
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<JournalReportFormat>(
            key: const ValueKey('journal-export-format'),
            initialValue: _format,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'File format'),
            items: [
              for (final format in JournalReportFormat.values)
                DropdownMenuItem(value: format, child: Text(format.label)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _format = value);
            },
          ),
          const SizedBox(height: 8),
          const Text(
            'CSV opens in spreadsheets. JSON also includes the exact filter '
            'settings.',
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            key: const ValueKey('journal-export-paths'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Include local file paths'),
            subtitle: const Text(
              'Paths can contain personal folder names. Book titles and '
              'listening times are included in every report.',
            ),
            value: _includeFilePaths,
            onChanged: (value) =>
                setState(() => _includeFilePaths = value ?? false),
          ),
          const SizedBox(height: 8),
          const Text(
            'This report is for reading and analysis. To make a restorable '
            'backup, use “Export library (JSON)” in Settings.',
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        key: const ValueKey('journal-export-cancel'),
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        key: const ValueKey('journal-export-confirm'),
        onPressed: () =>
            Navigator.pop(context, _ExportOptions(_format, _includeFilePaths)),
        child: const Text('Export'),
      ),
    ],
  );
}
