import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/providers.dart';
import '../utils/platform_utils.dart' as plat;

/// Onboarding — 3 pages:
/// 0: import books  •  1: background audio permission (POST_NOTIFICATIONS + READ_MEDIA_AUDIO)  •  2: done
/// Uses permission_handler; follows CrisperWeaver's permission pattern (mobile-only gate, try/catch, openAppSettings).
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _page = 0;

  // permission states
  PermissionStatus? _notifStatus;
  PermissionStatus? _audioStatus;
  bool _checkingPerms = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshPermissionStatus());
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool get _isDesktopWeb => kIsWeb || plat.isDesktop;

  Future<void> _refreshPermissionStatus() async {
    if (_isDesktopWeb) return;
    setState(() => _checkingPerms = true);
    try {
      final n = await Permission.notification.status;
      final a = await _audioPermission().status;
      if (!mounted) return;
      setState(() {
        _notifStatus = n;
        _audioStatus = a;
      });
    } catch (_) {
      // CrisperWeaver pattern: permission check failures are non-fatal
    } finally {
      if (mounted) setState(() => _checkingPerms = false);
    }
  }

  /// READ_MEDIA_AUDIO maps to Permission.audio on Android 13+;
  /// falls back to storage on older where .audio is not available.
  Permission _audioPermission() {
    // permission_handler 12 handles the mapping internally:
    // Permission.audio → READ_MEDIA_AUDIO (API 33+) else READ_EXTERNAL_STORAGE
    return Permission.audio;
  }

  Future<void> _requestPermissions() async {
    if (_isDesktopWeb) return;
    // CrisperWeaver pattern: only request on mobile, cheap no-op on desktop
    if (!(plat.isIOS || plat.isAndroid)) return;
    setState(() => _checkingPerms = true);
    try {
      final results = await [Permission.notification, _audioPermission()].request();
      if (!mounted) return;
      setState(() {
        _notifStatus = results[Permission.notification];
        _audioStatus = results[_audioPermission()];
      });
      if (!mounted) return;
      final allGranted = (_notifStatus?.isGranted ?? false) && (_audioStatus?.isGranted ?? false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(allGranted
              ? 'Permissions granted — background audio will work.'
              : 'Some permissions were not granted. You can enable them in Settings.'),
        ),
      );
    } catch (e) {
      debugPrint('permission request failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Permission request failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _checkingPerms = false);
    }
  }

  Future<void> _importBooks() async {
    final svc = ref.read(libraryServiceProvider);
    final paths = await svc.pickAudioFiles();
    if (paths.isEmpty) return;
    if (!mounted) return;
    // if multiple files, ask if they belong to one book or separate
    String? groupTitle;
    if (paths.length > 1) {
      groupTitle = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Import'),
          content: Text(
              '${paths.length} files selected. Import as single audiobook (e.g. multi-file book) or as separate books?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'separate'), child: const Text('Separate books')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'single'), child: const Text('Single book')),
          ],
        ),
      );
      if (groupTitle == null) return;
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (groupTitle == 'single') {
        await svc.importFiles(paths);
        messenger.showSnackBar(SnackBar(content: Text('Imported ${paths.length} files as one book')));
      } else if (groupTitle == 'separate') {
        for (final pth in paths) {
          await svc.importFiles([pth]);
        }
        messenger.showSnackBar(SnackBar(content: Text('Imported ${paths.length} books')));
      } else {
        await svc.importFiles(paths);
        messenger.showSnackBar(const SnackBar(content: Text('Book imported')));
      }
      // refresh library stream
      ref.invalidate(libraryBooksProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  Future<void> _finishOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    // also mark legacy/combined key for consistency
    await prefs.setBool('onboarding_completed', true);
    if (!mounted) return;
    context.go('/');
  }

  Future<void> _skipOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    await prefs.setBool('onboarding_completed', true);
    if (!mounted) return;
    context.go('/');
  }

  void _goTo(int page) {
    _pageController.animateToPage(page, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  void _next() {
    if (_page < 2) {
      _goTo(_page + 1);
    } else {
      _finishOnboarding();
    }
  }

  void _back() {
    if (_page > 0) _goTo(_page - 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // top bar: skip
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Text('CrisperPlayer', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton(onPressed: _skipOnboarding, child: const Text('Skip')),
                ],
              ),
            ),
            // page indicator
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: List.generate(3, (i) {
                  final active = i == _page;
                  final done = i < _page;
                  return Expanded(
                    child: Container(
                      height: 4,
                      margin: EdgeInsets.only(right: i == 2 ? 0 : 8),
                      decoration: BoxDecoration(
                        color: active || done ? cs.primary : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  );
                }),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _buildImportPage(context),
                  _buildPermissionsPage(context),
                  _buildDonePage(context),
                ],
              ),
            ),
            // bottom navigation
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: Row(
                children: [
                  if (_page > 0)
                    OutlinedButton(
                      onPressed: _back,
                      child: const Text('Back'),
                    )
                  else
                    const SizedBox(width: 80),
                  const Spacer(),
                  FilledButton(
                    onPressed: _next,
                    child: Text(_page == 2 ? 'Start listening' : 'Continue'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Page 0: Import books ──────────────────────────────────────────────
  Widget _buildImportPage(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final booksAsync = ref.watch(libraryBooksProvider);
    final importedCount = booksAsync.asData?.value.length ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(Icons.library_music, size: 64, color: cs.onPrimaryContainer),
          ),
          const SizedBox(height: 24),
          Text('Welcome to CrisperPlayer', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(
            'Import your audiobooks — m4b, m4a, mp3, flac, ogg, wav and more. We’ll track progress and bookmarks automatically.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (importedCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(12)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, size: 18, color: cs.onSecondaryContainer),
                  const SizedBox(width: 8),
                  Text('$importedCount book${importedCount == 1 ? '' : 's'} imported', style: TextStyle(color: cs.onSecondaryContainer, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          const SizedBox(height: 24),
          FilledButton.icon(
            icon: const Icon(Icons.file_open),
            label: const Text('Import audiobooks'),
            onPressed: _importBooks,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _next,
            child: const Text('I’ll do this later →'),
          ),
          const SizedBox(height: 16),
          Text(
            'You can always import more from the library screen.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── Page 1: Background audio permission ───────────────────────────────
  Widget _buildPermissionsPage(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final notifGranted = _notifStatus?.isGranted ?? false;
    final audioGranted = _audioStatus?.isGranted ?? false;
    final allGranted = notifGranted && audioGranted;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: cs.tertiaryContainer,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Icon(Icons.notifications_active_outlined, size: 64, color: cs.onTertiaryContainer),
          ),
          const SizedBox(height: 24),
          Text('Background audio', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(
            'Keep listening with the screen off, from your lock screen and headset. We need notification permission for playback controls and media access for your audio files.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (_isDesktopWeb)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: cs.primary),
                    const SizedBox(width: 12),
                    const Expanded(child: Text('No permissions needed on this platform — background audio works out of the box.')),
                  ],
                ),
              ),
            )
          else ...[
            _permTile(
              context,
              icon: Icons.notifications,
              title: 'Notifications (POST_NOTIFICATIONS)',
              subtitle: 'Playback notification & controls',
              status: _notifStatus,
              granted: notifGranted,
            ),
            const SizedBox(height: 10),
            _permTile(
              context,
              icon: Icons.audio_file,
              title: 'Media audio (READ_MEDIA_AUDIO)',
              subtitle: 'Read audiobooks from storage',
              status: _audioStatus,
              granted: audioGranted,
            ),
            const SizedBox(height: 20),
            if (_checkingPerms)
              const CircularProgressIndicator()
            else if (allGranted)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.check_circle, color: Colors.green, size: 20),
                    SizedBox(width: 8),
                    Text('All permissions granted', style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600)),
                  ],
                ),
              )
            else ...[
              FilledButton.icon(
                icon: const Icon(Icons.verified_user_outlined),
                label: const Text('Grant permissions'),
                onPressed: _requestPermissions,
              ),
              const SizedBox(height: 8),
              if (_notifStatus?.isPermanentlyDenied == true || _audioStatus?.isPermanentlyDenied == true)
                TextButton.icon(
                  icon: const Icon(Icons.settings),
                  label: const Text('Open system settings'),
                  onPressed: () => openAppSettings(),
                ),
            ],
            const SizedBox(height: 16),
            Text(
              'You can still use the app without these permissions — playback notification won’t show and files may not appear until access is granted.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6)),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 16),
          TextButton(onPressed: _next, child: const Text('Continue →')),
        ],
      ),
    );
  }

  Widget _permTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required PermissionStatus? status,
    required bool granted,
  }) {
    final cs = Theme.of(context).colorScheme;
    Color chipBg;
    Color chipFg;
    String chipLabel;
    IconData chipIcon;
    if (status == null) {
      chipBg = cs.surfaceContainerHighest;
      chipFg = cs.onSurface;
      chipLabel = 'Checking…';
      chipIcon = Icons.hourglass_empty;
    } else if (granted) {
      chipBg = Colors.green.withValues(alpha: 0.15);
      chipFg = Colors.green.shade700;
      chipLabel = 'Granted';
      chipIcon = Icons.check;
    } else if (status.isPermanentlyDenied) {
      chipBg = Colors.orange.withValues(alpha: 0.15);
      chipFg = Colors.orange.shade800;
      chipLabel = 'Denied';
      chipIcon = Icons.block;
    } else {
      chipBg = cs.errorContainer;
      chipFg = cs.onErrorContainer;
      chipLabel = 'Not granted';
      chipIcon = Icons.close;
    }

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: cs.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(subtitle, style: TextStyle(fontSize: 11, color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.7))),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: chipBg, borderRadius: BorderRadius.circular(20)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(chipIcon, size: 12, color: chipFg),
                  const SizedBox(width: 4),
                  Text(chipLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: chipFg)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Page 2: Done ──────────────────────────────────────────────────────
  Widget _buildDonePage(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Icon(Icons.check_circle_rounded, size: 64, color: Colors.green),
          ),
          const SizedBox(height: 24),
          Text('You’re all set!', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Text(
            'Dive into your audiobooks — resume where you left off, bookmark moments, and pick up from the lock screen.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.8)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Card(
            elevation: 0,
            color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _doneRow(context, Icons.play_circle_outline, 'Headset & lock-screen controls'),
                  const Divider(height: 20),
                  _doneRow(context, Icons.bookmark_outline, 'Manual & auto bookmarks'),
                  const Divider(height: 20),
                  _doneRow(context, Icons.history, 'Listening history grouped by day'),
                  const Divider(height: 20),
                  _doneRow(context, Icons.nightlight_round, 'Sleep timer & speed control'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.headphones),
              label: const Text('Start listening'),
              onPressed: _finishOnboarding,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You can change permissions and settings anytime from the Settings screen.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _doneRow(BuildContext context, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        const Icon(Icons.check, size: 16, color: Colors.green),
      ],
    );
  }
}
