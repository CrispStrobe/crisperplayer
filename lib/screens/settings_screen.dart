import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const Padding(padding: EdgeInsets.all(16), child: Text('Playback', style: TextStyle(fontWeight: FontWeight.bold))),
          ListTile(
            title: const Text('Default speed'),
            subtitle: Text('${settings.playbackSpeed.toStringAsFixed(2)}x'),
            trailing: Slider(value: settings.playbackSpeed, min: 0.5, max: 3.0, divisions: 10, label: '${settings.playbackSpeed}x', onChanged: (v){ settings.playbackSpeed=v; (context as Element).markNeedsBuild(); }),
          ),
          SwitchListTile(title: const Text('Skip silence'), value: settings.skipSilence, onChanged: (v){ settings.skipSilence=v; (context as Element).markNeedsBuild(); }),
          ListTile(title: const Text('Seek interval'), subtitle: Text('${settings.seekSeconds}s'), trailing: DropdownButton<int>(value: settings.seekSeconds, items: const [DropdownMenuItem(value:10, child: Text('10s')), DropdownMenuItem(value:15, child: Text('15s')), DropdownMenuItem(value:30, child: Text('30s')), DropdownMenuItem(value:60, child: Text('60s'))], onChanged: (v){ if(v!=null) {settings.seekSeconds=v; (context as Element).markNeedsBuild();}})),
          const Divider(),
          const Padding(padding: EdgeInsets.all(16), child: Text('Bookmarks & history', style: TextStyle(fontWeight: FontWeight.bold))),
          SwitchListTile(title: const Text('Auto-bookmark'), subtitle: const Text('Save position every 5 min & on pause'), value: settings.autoBookmarkEnabled, onChanged: (v){ settings.autoBookmarkEnabled=v; (context as Element).markNeedsBuild(); }),
          SwitchListTile(title: const Text('Resume on launch'), value: settings.resumeOnLaunch, onChanged: (v){ settings.resumeOnLaunch=v; (context as Element).markNeedsBuild(); }),
          const Divider(),
          const Padding(padding: EdgeInsets.all(16), child: Text('Appearance', style: TextStyle(fontWeight: FontWeight.bold))),
          ListTile(title: const Text('Theme'), subtitle: Text(settings.themeMode), trailing: DropdownButton<String>(value: settings.themeMode, items: const [DropdownMenuItem(value:'system', child: Text('System')), DropdownMenuItem(value:'light', child: Text('Light')), DropdownMenuItem(value:'dark', child: Text('Dark'))], onChanged: (v){ if(v!=null) {settings.themeMode=v; (context as Element).markNeedsBuild();}})),
          const SizedBox(height: 24),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('CrisperPlayer v0.1.0 • Plays m4b/m4a/mp3/flac/ogg/wav/aac/opus/wma and more. Native decoders (Android/iOS) handle m4b chapters as m4a + chapter table. All data stays on device.', style: TextStyle(fontSize: 11, color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6)))),
        ],
      ),
    );
  }
}
