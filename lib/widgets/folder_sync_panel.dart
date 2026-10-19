import '../services/sync/folder_progress_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';

class FolderSyncPanel extends ConsumerStatefulWidget {
  const FolderSyncPanel({super.key});
  @override
  ConsumerState<FolderSyncPanel> createState() => _FolderSyncPanelState();
}

class _FolderSyncPanelState extends ConsumerState<FolderSyncPanel> {
  bool _busy = false;
  String? _error;
  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Could not configure progress sync. Check the folder and passphrase.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _run(() => ref.read(folderProgressProvider).init()));
  }

  Future<void> _configure() async {
    final service = ref.read(folderProgressProvider);
    final sources = ref
        .read(remoteLibraryProvider)
        .connections
        .where(
          (c) => {'nextcloud', 'webdav', 'filen', 'internxt'}.contains(c.kind),
        )
        .toList();
    var id = sources.any((c) => c.id == service.connectionId)
        ? service.connectionId
        : sources.first.id;
    final folder = TextEditingController(text: service.folder),
        passphrase = TextEditingController();
    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Encrypted progress sync'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Choose an existing folder and use the same passphrase on every device. Only encrypted listening positions are uploaded. Audio stays on your devices. Each device needs its own copy of the same audio files.',
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: id,
                    items: [
                      for (final source in sources)
                        DropdownMenuItem(
                          value: source.id,
                          child: Text(source.name),
                        ),
                    ],
                    onChanged: (v) => id = v,
                  ),
                  TextField(
                    controller: folder,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Existing sync folder',
                      hintText: '/CrisperPlayerSync',
                    ),
                  ),
                  TextField(
                    controller: passphrase,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      labelText: 'Shared passphrase (12+ characters)',
                    ),
                  ),
                  const Text(
                    'Keep this passphrase: it cannot be recovered. A first sync fingerprints your audio and can take time for a large library.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Enable sync'),
            ),
          ],
        ),
      );
      if (accepted == true) {
        await _run(
          () => service.configure(
            connectionId: id,
            folder: folder.text.trim(),
            passphrase: passphrase.text,
          ),
        );
      }
    } finally {
      folder.dispose();
      passphrase.dispose();
    }
  }

  Future<void> _resolve(String bookId, String choice) => _run(() async {
    final playback = ref.read(playbackProvider);
    final open = playback.currentBookId == bookId;
    if (open && choice != 'local') await playback.unload();
    try {
      await ref
          .read(folderProgressProvider)
          .synchronize(resolveBookId: bookId, choice: choice);
    } finally {
      if (open && choice != 'local') await playback.loadBook(bookId);
    }
  });
  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(folderProgressProvider);
    return ExpansionTile(
      title: const Text('Encrypted cloud progress sync'),
      subtitle: Text(
        sync.enabled
            ? 'Enabled · ${sync.folder.isEmpty ? 'connection root' : sync.folder}'
            : 'Nextcloud / WebDAV / Filen / Internxt',
      ),
      children: [
        Wrap(
          spacing: 12,
          children: [
            TextButton(
              onPressed: _busy ? null : _configure,
              child: Text(sync.enabled ? 'Configure' : 'Set up'),
            ),
            if (sync.enabled)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        await sync.synchronize();
                      }),
                child: Text(_busy ? 'Syncing…' : 'Sync now'),
              ),
            if (sync.enabled)
              TextButton(
                onPressed: _busy ? null : () => _run(() => sync.configure()),
                child: const Text('Disable'),
              ),
          ],
        ),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
        for (final entry in sync.conflicts.entries)
          ListTile(
            title: const Text('Listening positions conflict'),
            subtitle: FutureBuilder(
              future: ref
                  .read(remoteLibraryProvider)
                  .library
                  .getBook(entry.key),
              builder: (_, data) => Text(data.data?.title ?? 'Audiobook'),
            ),
            trailing: PopupMenuButton<String>(
              enabled: !_busy,
              tooltip: 'Choose position',
              onSelected: (choice) => _resolve(entry.key, choice),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'local',
                  child: Text('Use this device'),
                ),
                for (final record in entry.value)
                  PopupMenuItem(
                    value: FolderProgressService.candidateId(record),
                    child: Text(
                      'Other device: track ${record.index + 1}, ${(record.positionMs / 1000).round()}s',
                    ),
                  ),
              ],
            ),
          ),
        for (final issue in sync.issues.entries)
          ListTile(
            title: Text(issue.value),
            trailing: issue.key == 'sync'
                ? null
                : TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            final playback = ref.read(playbackProvider);
                            final open = playback.currentBookId == issue.key;
                            if (open) await playback.unload();
                            try {
                              await sync.synchronize();
                            } finally {
                              if (open) await playback.loadBook(issue.key);
                            }
                          }),
                    child: const Text('Apply incoming'),
                  ),
          ),
      ],
    );
  }
}
