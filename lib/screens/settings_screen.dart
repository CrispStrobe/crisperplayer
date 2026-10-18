import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:go_router/go_router.dart';
import '../providers/providers.dart';
import '../services/db/app_database.dart';
import '../utils/platform_utils.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final db = ref.watch(appDatabaseProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Playback',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            title: const Text('Default speed'),
            subtitle: Text('${settings.playbackSpeed.toStringAsFixed(2)}x'),
            trailing: SizedBox(
              width: 160,
              child: Slider(
                value: settings.playbackSpeed,
                min: 0.5,
                max: 3.0,
                divisions: 10,
                label: '${settings.playbackSpeed}x',
                onChanged: (v) {
                  settings.playbackSpeed = v;
                },
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('Skip silence'),
            subtitle: isAndroid ? null : const Text('Available on Android'),
            value: isAndroid && settings.skipSilence,
            onChanged: isAndroid
                ? (v) {
                    settings.skipSilence = v;
                  }
                : null,
          ),
          ListTile(
            title: const Text('Seek interval'),
            subtitle: Text('${settings.seekSeconds}s'),
            trailing: DropdownButton<int>(
              value: settings.seekSeconds,
              items: const [
                DropdownMenuItem(value: 10, child: Text('10s')),
                DropdownMenuItem(value: 15, child: Text('15s')),
                DropdownMenuItem(value: 30, child: Text('30s')),
                DropdownMenuItem(value: 60, child: Text('60s')),
              ],
              onChanged: (v) {
                if (v != null) {
                  settings.seekSeconds = v;
                }
              },
            ),
          ),
          ListTile(
            title: const Text('Smart rewind amount'),
            subtitle: const Text('Rewind when resuming after a longer pause'),
            trailing: DropdownButton<int>(
              value: settings.smartRewindSeconds,
              items: [
                for (final n in {
                  0,
                  3,
                  5,
                  10,
                  15,
                  30,
                  60,
                  settings.smartRewindSeconds,
                }.toList()..sort())
                  DropdownMenuItem(
                    value: n,
                    child: Text(n == 0 ? 'Off' : '${n}s'),
                  ),
              ],
              onChanged: (v) {
                if (v != null) settings.smartRewindSeconds = v;
              },
            ),
          ),
          ListTile(
            title: const Text('Rewind after a pause longer than'),
            trailing: DropdownButton<int>(
              value: settings.smartRewindAfterSeconds,
              items: [
                for (final n in {
                  0,
                  30,
                  60,
                  120,
                  300,
                  600,
                  settings.smartRewindAfterSeconds,
                }.toList()..sort())
                  DropdownMenuItem(value: n, child: Text('${n}s')),
              ],
              onChanged: (v) {
                if (v != null) settings.smartRewindAfterSeconds = v;
              },
            ),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Bookmarks & history',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          SwitchListTile(
            title: const Text('Auto-bookmark'),
            subtitle: const Text('Save position every 5 min & on pause'),
            value: settings.autoBookmarkEnabled,
            onChanged: (v) {
              settings.autoBookmarkEnabled = v;
            },
          ),
          SwitchListTile(
            title: const Text('Resume on launch'),
            value: settings.resumeOnLaunch,
            onChanged: (v) {
              settings.resumeOnLaunch = v;
            },
          ),
          ListTile(
            leading: const Icon(Icons.history, size: 20),
            title: const Text('Clear listening history'),
            subtitle: const Text('Remove all history entries'),
            trailing: const Icon(Icons.chevron_right, size: 16),
            onTap: () => _confirmClearHistory(context, db),
          ),
          ListTile(
            leading: const Icon(Icons.bookmark_remove, size: 20),
            title: const Text('Clear bookmarks'),
            subtitle: const Text('Remove all auto & manual bookmarks'),
            trailing: const Icon(Icons.chevron_right, size: 16),
            onTap: () => _confirmClearBookmarks(context, db),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Data', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.upload_file, size: 20),
            title: const Text('Export library (JSON)'),
            subtitle: const Text(
              'Books, chapters, bookmarks & history → .json',
            ),
            trailing: const Icon(Icons.chevron_right, size: 16),
            onTap: () => _exportDb(context, db),
          ),
          ListTile(
            leading: const Icon(Icons.download, size: 20),
            title: const Text('Import library (JSON)'),
            subtitle: const Text('Restore from previously exported file'),
            trailing: const Icon(Icons.chevron_right, size: 16),
            onTap: () => _importDb(context, db),
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt, size: 20),
            title: const Text('Reset onboarding'),
            subtitle: const Text('Show onboarding again on next launch'),
            onTap: () => _resetOnboarding(context, settings),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Cloud', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_off),
            title: const Text('Cloud sync'),
            subtitle: const Text('Unavailable in this version'),
            onTap: () => context.push('/settings/sync'),
          ),
          const Divider(),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Appearance',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            title: const Text('Theme'),
            subtitle: Text(settings.themeMode),
            trailing: DropdownButton<String>(
              value: settings.themeMode,
              items: const [
                DropdownMenuItem(value: 'system', child: Text('System')),
                DropdownMenuItem(value: 'light', child: Text('Light')),
                DropdownMenuItem(value: 'dark', child: Text('Dark')),
              ],
              onChanged: (v) {
                if (v != null) {
                  settings.themeMode = v;
                }
              },
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'CrisperPlayer v0.1.0 • Plays m4b/m4a/mp3/flac/ogg/wav/aac/opus/wma and more. Native decoders (Android/iOS) handle m4b chapters as m4a + chapter table. All data stays on device.',
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(
                  context,
                ).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _confirmClearHistory(
    BuildContext context,
    AppDatabase db,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text(
          'This will permanently delete all listening history. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await db.clearAllHistory();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('History cleared')));
      }
    }
  }

  Future<void> _confirmClearBookmarks(
    BuildContext context,
    AppDatabase db,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear bookmarks?'),
        content: const Text(
          'This will delete all bookmarks (manual & auto). This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await db.clearAllBookmarks();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Bookmarks cleared')));
      }
    }
  }

  Future<void> _exportDb(BuildContext context, AppDatabase db) async {
    try {
      final data = await db.exportAllJson();
      final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
      final countBooks = (data['books'] as List).length;
      final countBms = (data['bookmarks'] as List).length;
      final countHist = (data['history'] as List).length;
      if (kIsWeb) {
        if (!context.mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Export preview'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Books: $countBooks • Bookmarks: $countBms • History: $countHist',
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    jsonStr.substring(
                      0,
                      jsonStr.length > 4000 ? 4000 : jsonStr.length,
                    ),
                    style: const TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          ),
        );
        return;
      }
      final dir = await getApplicationDocumentsDirectory();
      final file = File(
        '${dir.path}/crisperplayer_export_${DateTime.now().millisecondsSinceEpoch}.json',
      );
      await file.writeAsString(jsonStr);
      try {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            text: 'CrisperPlayer export — $countBooks books',
          ),
        );
      } catch (_) {}
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported $countBooks books to ${file.path}')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  Future<void> _importDb(BuildContext context, AppDatabase db) async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (files.isEmpty) return;
      final data =
          jsonDecode(utf8.decode(await files.first.readAsBytes()))
              as Map<String, dynamic>;
      if (data['books'] is! List) {
        throw const FormatException('Missing books in library export');
      }
      final books = (data['books'] as List).length;
      final bookmarks = (data['bookmarks'] as List? ?? []).length;
      final history = (data['history'] as List? ?? []).length;
      if (!context.mounted) return;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Import library?'),
          content: Text(
            'Merge $books books, $bookmarks bookmarks and $history history entries? '
            'Matching IDs will be updated. Audio files must still be accessible on this device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Import'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
      await db.importAllJson(data);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Imported $books books')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    }
  }

  Future<void> _resetOnboarding(BuildContext context, dynamic settings) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset onboarding?'),
        content: const Text(
          'Onboarding will show again when you restart the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok == true) {
      settings.onboardingDone = false;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Onboarding will show on next launch')),
        );
      }
    }
  }
}
