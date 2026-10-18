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
  Future<void> _connect() async {
    final name = TextEditingController(), url = TextEditingController();
    final username = TextEditingController(), secret = TextEditingController();
    var kind = 'plex', localHttp = false, connecting = false;
    String? error;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => PopScope(
          canPop: !connecting,
          child: AlertDialog(
            title: const Text('Add server'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: kind,
                      decoration: const InputDecoration(labelText: 'Source'),
                      items: const [
                        DropdownMenuItem(value: 'plex', child: Text('Plex')),
                        DropdownMenuItem(
                          value: 'webdav',
                          child: Text('WebDAV / NAS'),
                        ),
                      ],
                      onChanged: connecting
                          ? null
                          : (value) => update(() => kind = value!),
                    ),
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(
                        labelText: 'Connection name',
                      ),
                    ),
                    TextField(
                      controller: url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Server URL',
                        hintText: 'https://server.example.com/',
                      ),
                    ),
                    if (kind == 'webdav')
                      TextField(
                        controller: username,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                        ),
                      ),
                    TextField(
                      controller: secret,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        labelText: kind == 'plex'
                            ? 'X-Plex-Token'
                            : 'Password / app password',
                      ),
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: localHttp,
                      onChanged: connecting
                          ? null
                          : (v) => update(() => localHttp = v!),
                      title: const Text('Allow HTTP on the local network'),
                      subtitle: const Text(
                        'For a private IP address or .local hostname. Credentials travel without encryption.',
                      ),
                    ),
                    if (kind == 'plex')
                      const Text(
                        'Use a Plex music library with one album per audiobook. Enter the server address and your Plex token.',
                      ),
                    if (error != null)
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (connecting) const LinearProgressIndicator(),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: connecting ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: connecting
                    ? null
                    : () async {
                        update(() {
                          connecting = true;
                          error = null;
                        });
                        try {
                          await service.connect(
                            name: name.text,
                            kind: kind,
                            url: url.text,
                            username: username.text,
                            secret: secret.text,
                            allowLocalHttp: localHttp,
                          );
                          if (context.mounted) Navigator.pop(context);
                        } catch (e) {
                          update(() {
                            connecting = false;
                            error = '$e';
                          });
                        }
                      },
                child: const Text('Connect'),
              ),
            ],
          ),
        ),
      ),
    );
    name.dispose();
    url.dispose();
    username.dispose();
    secret.dispose();
  }

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
                      'Browse Plex or WebDAV servers and download books for offline listening. Credentials stay in secure storage. Downloads have independent progress on this device.\n\nFor SMB shares, mount the share in your operating system and use Import folder from the library, or select files through your device’s Files app.',
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
              trailing: selected.kind == 'webdav' && _trail.length > 1
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
