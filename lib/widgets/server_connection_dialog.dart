import 'package:flutter/material.dart';
import '../services/server/remote_library_service.dart';
import '../services/server/sftp_reader.dart';

class ServerConnectionDialog extends StatefulWidget {
  final RemoteLibraryService service;
  const ServerConnectionDialog({super.key, required this.service});
  @override
  State<ServerConnectionDialog> createState() => _ServerConnectionDialogState();
}

class _ServerConnectionDialogState extends State<ServerConnectionDialog> {
  final _name = TextEditingController(), _url = TextEditingController();
  final _username = TextEditingController(), _secret = TextEditingController();
  String _kind = 'plex';
  String? _error, _hostKey;
  bool _localHttp = false, _connecting = false, _trustHostKey = false;
  void _clearTrust() {
    _hostKey = null;
    _trustHostKey = false;
    _error = null;
  }

  Future<void> _connect() async {
    if (_connecting) return;
    if (_kind == 'sftp' && _hostKey != null && !_trustHostKey) {
      setState(() => _error = 'Verify and trust the server key to connect.');
      return;
    }
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      await widget.service.connect(
        name: _name.text,
        kind: _kind,
        url: _url.text,
        username: _username.text,
        secret: _secret.text,
        allowLocalHttp: _localHttp,
        hostKey: _trustHostKey ? _hostKey : null,
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = '$error';
        if (error is SftpHostKeyException) {
          _hostKey = error.fingerprint;
          _trustHostKey = false;
        }
      });
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _username.dispose();
    _secret.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_connecting,
    child: AlertDialog(
      title: const Text('Add server'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _kind,
                decoration: const InputDecoration(labelText: 'Source'),
                items: const [
                  DropdownMenuItem(value: 'plex', child: Text('Plex')),
                  DropdownMenuItem(
                    value: 'webdav',
                    child: Text('WebDAV / NAS'),
                  ),
                  DropdownMenuItem(value: 'sftp', child: Text('SFTP / NAS')),
                ],
                onChanged: _connecting
                    ? null
                    : (value) => setState(() {
                        _kind = value!;
                        _clearTrust();
                      }),
              ),
              TextField(
                controller: _name,
                enabled: !_connecting,
                decoration: const InputDecoration(labelText: 'Connection name'),
              ),
              TextField(
                controller: _url,
                enabled: !_connecting,
                autocorrect: false,
                onChanged: (_) => setState(_clearTrust),
                decoration: InputDecoration(
                  labelText: 'Server URL',
                  hintText: _kind == 'sftp'
                      ? 'sftp://nas.local/books/'
                      : 'https://server.example.com/',
                ),
              ),
              if (_kind != 'plex')
                TextField(
                  controller: _username,
                  enabled: !_connecting,
                  autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Username'),
                ),
              TextField(
                controller: _secret,
                enabled: !_connecting,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: _kind == 'plex'
                      ? 'X-Plex-Token'
                      : 'Password / app password',
                ),
              ),
              if (_kind != 'sftp')
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _localHttp,
                  onChanged: _connecting
                      ? null
                      : (value) => setState(() => _localHttp = value!),
                  title: const Text('Allow HTTP on the local network'),
                  subtitle: const Text(
                    'For a private IP address or .local hostname. Credentials travel without encryption.',
                  ),
                ),
              if (_kind == 'sftp' && _hostKey != null) ...[
                SelectableText('SSH host key: $_hostKey'),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _trustHostKey,
                  onChanged: _connecting
                      ? null
                      : (v) => setState(() => _trustHostKey = v!),
                  title: const Text('Trust this server key'),
                  subtitle: const Text(
                    'Compare the fingerprint with your NAS or SSH administrator.',
                  ),
                ),
              ],
              if (_kind == 'plex')
                const Text(
                  'Use a Plex music library with one album per audiobook. Enter the server address and your Plex token.',
                ),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (_connecting) const LinearProgressIndicator(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _connecting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _connecting ? null : _connect,
          child: const Text('Connect'),
        ),
      ],
    ),
  );
}
