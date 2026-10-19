import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';

class PlexSyncPanel extends ConsumerStatefulWidget {
  const PlexSyncPanel({super.key});
  @override
  ConsumerState<PlexSyncPanel> createState() => _PlexSyncPanelState();
}

class _PlexSyncPanelState extends ConsumerState<PlexSyncPanel> {
  bool _busy = false;
  String? _error;
  Future<void> _run(Future<void> Function() operation) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await operation();
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not update sync. Your local progress is safe.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _run(() => ref.read(plexProgressProvider).init()));
  }

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(plexProgressProvider);
    final remote = ref.watch(remoteLibraryProvider);
    final plex = remote.connections.where((c) => c.kind == 'plex').toList();
    if (plex.isEmpty) return const SizedBox.shrink();
    return ExpansionTile(
      title: const Text('Plex progress sync'),
      children: [
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text(
            'Optional: share listening positions with Plex. Enable “Store track progress” in your Plex music library. Concurrent changes require a choice. Incoming positions apply after closing the book.',
          ),
        ),
        for (final connection in plex)
          SwitchListTile(
            title: Text(connection.name),
            value: sync.enabled.contains(connection.id),
            onChanged: _busy
                ? null
                : (v) => _run(() => sync.setEnabled(connection.id, v)),
          ),
        TextButton.icon(
          onPressed: _busy
              ? null
              : () => _run(() async {
                  await sync.synchronize();
                }),
          icon: const Icon(Icons.sync),
          label: Text(_busy ? 'Syncing…' : 'Sync now'),
        ),
        if (_error != null) Text(_error!),
        for (final id in sync.conflicts)
          ListTile(
            title: const Text('Listening positions conflict'),
            subtitle: FutureBuilder(
              future: ref.read(libraryServiceProvider).getBook(id),
              builder: (_, snapshot) =>
                  Text(snapshot.data?.title ?? 'Audiobook'),
            ),
            trailing: PopupMenuButton<String>(
              enabled: !_busy,
              tooltip: 'Choose listening position',
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'local', child: Text('Use this device')),
                PopupMenuItem(value: 'remote', child: Text('Use Plex')),
              ],
              onSelected: (choice) => _run(() async {
                final playback = ref.read(playbackProvider);
                final open = playback.currentBookId == id;
                if (open && choice == 'remote') await playback.unload();
                await sync.synchronize(bookId: id, choice: choice);
                if (open && choice == 'remote') await playback.loadBook(id);
              }),
            ),
          ),
        for (final issue in sync.issues.entries)
          ListTile(
            title: Text(issue.value),
            trailing: issue.value.startsWith('Remote progress is ready')
                ? TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            final playback = ref.read(playbackProvider);
                            final open = playback.currentBookId == issue.key;
                            if (open) await playback.unload();
                            try {
                              await sync.synchronize(
                                bookId: issue.key,
                                choice: 'remote',
                              );
                            } finally {
                              if (open) await playback.loadBook(issue.key);
                            }
                          }),
                    child: const Text('Apply Plex position'),
                  )
                : null,
          ),
      ],
    );
  }
}
