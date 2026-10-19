import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../providers/providers.dart';
import '../services/transfer/browser_upload_server.dart';

class BrowserUploadScreen extends ConsumerStatefulWidget {
  const BrowserUploadScreen({super.key});
  @override
  ConsumerState<BrowserUploadScreen> createState() =>
      _BrowserUploadScreenState();
}

class _BrowserUploadScreenState extends ConsumerState<BrowserUploadScreen>
    with WidgetsBindingObserver {
  BrowserUploadServer? _server;
  bool _working = false;
  String? _message;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Permission prompts briefly make iOS inactive, so only stop on hidden/paused.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(_stop());
    }
  }

  Future<void> _start() async {
    if (_working || _server != null) return;
    setState(() {
      _working = true;
      _message = null;
    });
    final library = ref.read(libraryServiceProvider);
    final server = BrowserUploadServer(
      temporaryDirectory: getTemporaryDirectory,
      importBook: (paths, title) =>
          library.importFiles(paths, title: title, preserveOrder: true),
    );
    _server = server;
    try {
      await server.start();
      if (!mounted || _server != server) {
        await server.stop();
        return;
      }
      if (server.addresses.isEmpty) {
        await server.stop();
        _server = null;
        _message =
            'No local IPv4 address found. Connect to Wi-Fi and try again.';
      }
    } catch (_) {
      await server.stop();
      if (_server == server) _server = null;
      _message =
          'Could not start sharing. Check your local network permission and Wi-Fi connection.';
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _stop() async {
    final server = _server;
    if (server == null) return;
    if (mounted) {
      setState(() {
        _working = true;
        _message = 'Stopping sharing…';
      });
    }
    var message = 'Sharing stopped. Unfinished uploads were discarded.';
    try {
      await server.stop();
    } catch (_) {
      message =
          'Sharing stopped, but temporary file cleanup could not complete.';
    }
    if (_server == server) _server = null;
    if (mounted) {
      setState(() {
        _working = false;
        _message = message;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _server?.stop().ignore();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final server = _server;
    return Scaffold(
      appBar: AppBar(title: const Text('Upload from browser')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.wifi, size: 56),
          const SizedBox(height: 16),
          Text(
            'Send audiobooks to this device',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          const Text(
            'Connect both devices to the same trusted Wi-Fi network. Start sharing, then open the address below in a browser on your computer.',
          ),
          const SizedBox(height: 12),
          const Text(
            'Keep this screen open and the device unlocked during transfer. Sharing stops when the app goes into the background or you leave this screen. HTTP uploads are not encrypted; use a trusted private network.',
          ),
          const SizedBox(height: 20),
          if (server != null && server.port != 0) ...[
            for (final address in server.addresses)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: SelectableText(address),
                trailing: IconButton(
                  tooltip: 'Copy address',
                  icon: const Icon(Icons.copy),
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: address)),
                ),
              ),
            const Text('Access code — paste this into the browser'),
            const SizedBox(height: 8),
            SelectableText(server.accessCode),
            TextButton.icon(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: server.accessCode)),
              icon: const Icon(Icons.copy),
              label: const Text('Copy access code'),
            ),
            const Text(
              'Select all tracks for one book. They are sorted by filename and imported together. Repeat for the next book.',
            ),
          ],
          if (_message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(_message!),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _working
                ? null
                : server == null
                ? _start
                : _stop,
            icon: Icon(server == null ? Icons.wifi : Icons.stop),
            label: Text(
              _working
                  ? 'Please wait…'
                  : server == null
                  ? 'Start sharing'
                  : 'Stop sharing',
            ),
          ),
        ],
      ),
    );
  }
}
