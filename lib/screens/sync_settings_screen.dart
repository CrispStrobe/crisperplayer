import '../widgets/server_connection_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';
import '../services/server/remote_client.dart';
import '../services/server/remote_library_service.dart';

class SyncSettingsScreen extends ConsumerStatefulWidget {
  const SyncSettingsScreen({super.key});
  @override
  ConsumerState<SyncSettingsScreen> createState() => _RemoteLibraryState();
}

class _RemoteLibraryState extends ConsumerState<SyncSettingsScreen> {
  String? _connectionId, _error;
  final List<({String path, String name})> _trail = [];
  List<RemoteEntry> _entries = [];
  bool _loading = false;
  RemoteLibraryService get service => ref.read(remoteLibraryProvider);
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => _run(() async {
        await service.init();
      }),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _browse(String path, String name, {bool back = false}) =>
      _run(() async {
        final entries = await service.browse(_connectionId!, path);
        if (!mounted) return;
        setState(() {
          _entries = entries;
          if (back) {
            _trail.removeLast();
          } else {
            _trail.add((path: path, name: name));
          }
        });
      });
  Future<void> _download(RemoteEntry entry, {bool file = false}) =>
      _run(() async {
        await service.download(
          _connectionId!,
          entry.path,
          entry.name,
          author: entry.author,
          file: file,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Book available offline in your library'),
            ),
          );
        }
      });
  Future<void> _connect() => showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => ServerConnectionDialog(service: service),
  );

  @override
  Widget build(BuildContext context) {
    final remote = ref.watch(remoteLibraryProvider);
    final selected = remote.connections
        .where((c) => c.id == _connectionId)
        .firstOrNull;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Servers & NAS'),
        actions: [
          IconButton(
            onPressed: _loading || remote.busy ? null : _connect,
            icon: const Icon(Icons.add),
            tooltip: 'Add server',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading || remote.busy) const LinearProgressIndicator(),
          if (remote.busy)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Downloading ${remote.downloadName} · ${(remote.downloadedBytes / 1048576).toStringAsFixed(1)} MB',
              ),
            ),
          if (remote.busy)
            TextButton.icon(
              onPressed: remote.canPause ? remote.pauseDownload : null,
              icon: const Icon(Icons.pause),
              label: Text(
                remote.canPause ? 'Pause download' : 'Finishing import…',
              ),
            ),
          if (remote.downloads.isNotEmpty)
            ExpansionTile(
              title: Text('Downloads (${remote.downloads.length})'),
              children: [
                SizedBox(
                  height: 180,
                  child: ListView(
                    children: [
                      for (final job in remote.downloads)
                        ListTile(
                          title: Text(job.title),
                          subtitle: Text(
                            '${job.phase} · ${(job.bytes / 1048576).toStringAsFixed(1)} MB${job.error == null ? '' : '\n${job.error}'}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Resume download',
                                onPressed: _loading || remote.busy
                                    ? null
                                    : () => _run(() async {
                                        await remote.resume(job.id);
                                      }),
                                icon: const Icon(Icons.play_arrow),
                              ),
                              IconButton(
                                tooltip: 'Discard download',
                                onPressed: _loading || remote.busy
                                    ? null
                                    : () => _run(() => remote.discard(job.id)),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (selected == null)
            Expanded(
              child: ListView(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Browse Plex, WebDAV or SFTP servers and download books for offline listening. Credentials stay in secure storage. Downloads have independent progress on this device.\n\nFor SMB shares, mount the share in your operating system and use Import folder from the library, or select files through your device’s Files app.',
                    ),
                  ),
                  for (final c in remote.connections)
                    ListTile(
                      leading: Icon(
                        c.kind == 'plex'
                            ? Icons.video_library_outlined
                            : Icons.dns_outlined,
                      ),
                      title: Text(c.name),
                      subtitle: Text(c.url.toString()),
                      onTap: _loading
                          ? null
                          : () {
                              _connectionId = c.id;
                              _trail.clear();
                              _browse('', c.name);
                            },
                      trailing: IconButton(
                        tooltip: 'Disconnect',
                        icon: const Icon(Icons.link_off),
                        onPressed: _loading || remote.busy
                            ? null
                            : () => _run(() => remote.disconnect(c.id)),
                      ),
                    ),
                ],
              ),
            )
          else ...[
            ListTile(
              leading: IconButton(
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back),
                onPressed: _loading || remote.busy
                    ? null
                    : () {
                        if (_trail.length <= 1) {
                          setState(() {
                            _connectionId = null;
                            _trail.clear();
                          });
                        } else {
                          final parent = _trail[_trail.length - 2];
                          _browse(parent.path, parent.name, back: true);
                        }
                      },
              ),
              title: Text(_trail.lastOrNull?.name ?? selected.name),
              trailing: selected.kind != 'plex' && _trail.isNotEmpty
                  ? TextButton.icon(
                      onPressed: _loading || remote.busy
                          ? null
                          : () => _download(
                              RemoteEntry(
                                _trail.last.path,
                                _trail.last.name,
                                'folder',
                              ),
                            ),
                      icon: const Icon(Icons.download),
                      label: const Text('Download folder as book'),
                    )
                  : null,
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final e in _entries)
                    if (e.type != 'file' || RemoteClient.isAudio(e.name))
                      ListTile(
                        leading: Icon(
                          e.type == 'folder'
                              ? Icons.folder_outlined
                              : e.type == 'book'
                              ? Icons.menu_book
                              : Icons.audio_file_outlined,
                        ),
                        title: Text(e.name),
                        subtitle: e.author.isEmpty ? null : Text(e.author),
                        trailing: e.type == 'folder'
                            ? const Icon(Icons.chevron_right)
                            : const Icon(Icons.download),
                        onTap: _loading || remote.busy
                            ? null
                            : () => e.type == 'folder'
                                  ? _browse(e.path, e.name)
                                  : _download(e, file: e.type == 'file'),
                      ),
                  if (_entries.isEmpty && !_loading)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No items in this folder.'),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
