import 'package:flutter/material.dart';

class SyncSettingsScreen extends StatelessWidget {
  const SyncSettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Cloud sync')),
        body: const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
                'Cloud sync is unavailable in this version. Your library, progress and '
                'bookmarks are stored on this device. Use Export library in Settings to '
                'back up metadata. Audio files are not included in the export.')),
      );
}
