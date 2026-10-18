import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

const appRepository = 'https://github.com/CrispStrobe/crisperplayer';
const appWebsite = 'https://crispstrobe.github.io/crisperplayer/';

Future<void> showAppAboutDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const AppAboutDialog());

/// The same provider/contact/privacy/license structure as CrisperWeaver.
class AppAboutDialog extends StatefulWidget {
  const AppAboutDialog({super.key});
  @override
  State<AppAboutDialog> createState() => _AppAboutDialogState();
}

class _AppAboutDialogState extends State<AppAboutDialog> {
  late final _info = PackageInfo.fromPlatform();

  Future<void> _open(String address) async {
    final opened = await launchUrl(
      Uri.parse(address),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No application could open this link.')),
      );
    }
  }

  Widget _section(String title, String body) => Padding(
    padding: const EdgeInsets.only(top: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        SelectableText(body),
      ],
    ),
  );

  Widget _link(String label, String address) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    trailing: const Icon(Icons.open_in_new, size: 20),
    onTap: () => _open(address),
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('About CrisperPlayer'),
    content: SizedBox(
      width: 560,
      height: MediaQuery.sizeOf(context).height * .65,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.asset(
                'assets/branding/app-icon-source.png',
                width: 72,
                height: 72,
                excludeFromSemantics: true,
              ),
            ),
            const SizedBox(height: 12),
            const Text('Your audiobooks. Your place. On your device.'),
            FutureBuilder<PackageInfo>(
              future: _info,
              builder: (_, snapshot) => Text(
                snapshot.hasData
                    ? 'Version ${snapshot.data!.version} (${snapshot.data!.buildNumber})'
                    : 'CrisperPlayer',
              ),
            ),
            _section(
              'Service provider',
              'Christian Ströbele\nNikolausstr. 5\n70190 Stuttgart\nDeutschland / Germany',
            ),
            _section('Contact', 'Questions, feedback and support'),
            _link('postmaster@crispstro.be', 'mailto:postmaster@crispstro.be'),
            _link('+49 176 6421 8601', 'tel:+4917664218601'),
            _link('Source code and issue tracker', appRepository),
            _link('Website and downloads', appWebsite),
            _section(
              'Privacy',
              'Your library, listening position, bookmarks and history are stored on this device. Audio imports are copied into app storage. Server connections contact only the Plex or NAS address you configure; credentials use the platform secure store. There is no analytics or automatic cross-device sync. Metadata exports do not include your audio files or server passwords.',
            ),
            _section(
              'Playback and storage',
              'Android, iOS and macOS use native audio playback. Windows and Linux use media_kit / libmpv. The local database uses SQLite. SMB2/3 access uses libsmb2 through dart_smb2. Codec support depends on the platform and decoder.',
            ),
            _section(
              'Disclaimer',
              'Provided as is, without warranties of any kind, to the extent permitted by law. Keep backups of your audio and library metadata. You are responsible for having permission to use the audio you import.',
            ),
            _section(
              'Open-source licenses',
              'Flutter and Dart dependency licenses, native library notices and source references are available below. CrisperPlayer is licensed under GNU AGPL-3.0. Third-party components retain their upstream licenses.',
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.article_outlined),
              label: const Text('View licenses'),
              onPressed: () async {
                final info = await _info;
                if (!context.mounted) return;
                showLicensePage(
                  context: context,
                  applicationName: 'CrisperPlayer',
                  applicationVersion: '${info.version}+${info.buildNumber}',
                );
              },
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}
