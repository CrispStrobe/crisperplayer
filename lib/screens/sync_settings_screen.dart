import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../services/sync_service.dart';

class SyncSettingsScreen extends ConsumerStatefulWidget {
  const SyncSettingsScreen({super.key});

  @override
  ConsumerState<SyncSettingsScreen> createState() => _SyncSettingsScreenState();
}

class _SyncSettingsScreenState extends ConsumerState<SyncSettingsScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _showLoginForm = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  String _fmtLastSync(DateTime? dt) {
    if (dt == null) return 'Never';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('MMM d, yyyy HH:mm').format(dt);
  }

  Color _statusColor(SyncStatus s, BuildContext ctx) {
    final cs = Theme.of(ctx).colorScheme;
    return switch (s) {
      SyncStatus.success => Colors.green,
      SyncStatus.syncing => cs.primary,
      SyncStatus.error => cs.error,
      SyncStatus.offline => Colors.orange,
      SyncStatus.idle => cs.outline,
    };
  }

  IconData _statusIcon(SyncStatus s) => switch (s) {
        SyncStatus.success => Icons.check_circle,
        SyncStatus.syncing => Icons.sync,
        SyncStatus.error => Icons.error_outline,
        SyncStatus.offline => Icons.cloud_off,
        SyncStatus.idle => Icons.cloud_queue,
      };

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(syncServiceProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cloud Sync'),
        actions: [
          if (sync.isLoggedIn)
            IconButton(
              tooltip: 'Add demo conflict',
              icon: const Icon(Icons.bug_report_outlined, size: 20),
              onPressed: () => sync.addDemoConflict(),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          // ── Sync toggle header ──
          _SectionHeader(icon: Icons.cloud_sync, title: 'Sync'),
          SwitchListTile(
            secondary: Icon(
              sync.syncEnabled ? Icons.cloud_done : Icons.cloud_off,
              color: sync.syncEnabled ? cs.primary : null,
            ),
            title: const Text('Enable cloud sync'),
            subtitle: Text(sync.syncEnabled
                ? 'Progress, bookmarks & history sync across devices'
                : 'Sync is paused — manual sync still available when signed in'),
            value: sync.syncEnabled,
            onChanged: (v) => sync.toggleSync(v),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.autorenew),
            title: const Text('Auto-sync'),
            subtitle: const Text('Sync on app pause & when enabled'),
            value: sync.autoSync,
            onChanged: sync.syncEnabled || sync.isLoggedIn
                ? (v) => setState(() => sync.autoSync = v)
                : null,
          ),

          // ── Sync status card ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(_statusIcon(sync.status),
                            size: 20, color: _statusColor(sync.status, context)),
                        const SizedBox(width: 8),
                        Text('Status: ${sync.status.label}',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: _statusColor(sync.status, context))),
                        const Spacer(),
                        if (sync.isSyncing)
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                          ),
                      ],
                    ),
                    if (sync.isSyncing) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(value: sync.progress == 0 ? null : sync.progress),
                      const SizedBox(height: 4),
                      Text('${(sync.progress * 100).toStringAsFixed(0)}% • Uploading & merging…',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                    if (sync.status == SyncStatus.error && (sync.errorMessage ?? sync.lastError) != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: cs.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 16, color: cs.onErrorContainer),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(sync.errorMessage ?? sync.lastError ?? 'Unknown error',
                                  style: TextStyle(fontSize: 12, color: cs.onErrorContainer)),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.schedule, size: 14, color: cs.outline),
                        const SizedBox(width: 6),
                        Text('Last sync: ${_fmtLastSync(sync.lastSyncTime)}',
                            style: Theme.of(context).textTheme.bodySmall),
                        const Spacer(),
                        Text(sync.isLoggedIn ? sync.accountEmail! : 'Not signed in',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: cs.outline)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: sync.isSyncing
                            ? null
                            : sync.isLoggedIn
                                ? () => sync.syncNow()
                                : null,
                        icon: Icon(sync.isSyncing ? Icons.hourglass_top : Icons.sync),
                        label: Text(sync.isSyncing ? 'Syncing…' : 'Sync now'),
                      ),
                    ),
                    if (!sync.isLoggedIn)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('Sign in to enable sync',
                            style: TextStyle(fontSize: 11, color: cs.outline)),
                      ),
                    if (!sync.syncEnabled && sync.isLoggedIn)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('Tip: enable auto-sync to keep devices in sync automatically',
                            style: TextStyle(fontSize: 11, color: cs.outline)),
                      ),
                  ],
                ),
              ),
            ),
          ),

          const Divider(),

          // ── Account ──
          _SectionHeader(
            icon: Icons.person_outline,
            title: 'Account',
            trailing: sync.isLoggedIn
                ? Chip(
                    label: const Text('Signed in', style: TextStyle(fontSize: 11)),
                    backgroundColor: Colors.green.withValues(alpha: 0.15),
                    side: BorderSide(color: Colors.green.withValues(alpha: 0.3)),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  )
                : Chip(
                    label: const Text('Not signed in', style: TextStyle(fontSize: 11)),
                    backgroundColor: cs.surfaceContainerHighest,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
          ),
          if (!sync.isLoggedIn) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Sign in with your Supabase account to sync library, progress and bookmarks. '
                    'This is a placeholder — wiring real Supabase is a 1-line change in SyncService.signIn.',
                    style: TextStyle(fontSize: 12, color: cs.outline),
                  ),
                  const SizedBox(height: 12),
                  if (!_showLoginForm) ...[
                    FilledButton.icon(
                      onPressed: () => setState(() => _showLoginForm = true),
                      icon: const Icon(Icons.login),
                      label: const Text('Sign in with email'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final ok = await sync.signInWithProvider('google');
                        if (ok && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Signed in as ${sync.accountEmail}')),
                          );
                        }
                      },
                      icon: const Icon(Icons.g_mobiledata, size: 24),
                      label: const Text('Continue with Google'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final ok = await sync.signInWithProvider('apple');
                        if (ok && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Signed in as ${sync.accountEmail}')),
                          );
                        }
                      },
                      icon: const Icon(Icons.apple),
                      label: const Text('Continue with Apple'),
                    ),
                  ] else ...[
                    TextField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _passCtrl,
                      obscureText: _obscure,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility, size: 18),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      onSubmitted: (_) => _doSignIn(sync),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: sync.isSyncing ? null : () => _doSignIn(sync),
                            child: sync.isSyncing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text('Sign in'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        TextButton(
                          onPressed: () => setState(() => _showLoginForm = false),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                    TextButton(
                      onPressed: () => _showInfoDialog(
                        context,
                        'Supabase setup',
                        'To wire real Supabase Auth:\n\n'
                            '1. Add supabase_flutter to pubspec.yaml\n'
                            '2. Init in main(): await Supabase.initialize(url: ..., anonKey: ...)\n'
                            '3. Replace SyncService.signIn body with:\n'
                            '   Supabase.instance.client.auth.signInWithPassword(email: email, password: password)\n'
                            '4. Listen to auth state changes for token refresh.',
                      ),
                      child: const Text('How to connect Supabase →'),
                    ),
                  ],
                ],
              ),
            ),
          ] else ...[
            ListTile(
              leading: CircleAvatar(
                backgroundColor: cs.primaryContainer,
                child: Text(
                  (sync.accountEmail![0]).toUpperCase(),
                  style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.bold),
                ),
              ),
              title: Text(sync.accountEmail!, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text('Token: ${(sync.authToken ?? '').substring(0, (sync.authToken?.length ?? 0).clamp(0, 18))}…',
                  style: TextStyle(fontSize: 11, color: cs.outline)),
              trailing: TextButton(
                onPressed: () => _confirmSignOut(context, sync),
                child: const Text('Sign out'),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton.icon(
                onPressed: () => _confirmSignOut(context, sync),
                icon: const Icon(Icons.logout, size: 16),
                label: const Text('Sign out'),
              ),
            ),
          ],

          const Divider(),

          // ── Conflict resolution ──
          _SectionHeader(icon: Icons.merge, title: 'Conflict resolution'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'When the same book was played on two devices, which progress wins?',
              style: TextStyle(fontSize: 12, color: cs.outline),
            ),
          ),
          ...ConflictStrategy.values.map((strat) {
            final selected = sync.conflictStrategy == strat;
            return RadioListTile<ConflictStrategy>(
              value: strat,
              groupValue: sync.conflictStrategy,
              title: Text(strat.label, style: TextStyle(fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
              subtitle: Text(strat.description, style: const TextStyle(fontSize: 11)),
              secondary: Icon(
                switch (strat) {
                  ConflictStrategy.keepLocal => Icons.phone_iphone,
                  ConflictStrategy.keepRemote => Icons.cloud_done,
                  ConflictStrategy.keepNewest => Icons.schedule,
                  ConflictStrategy.askEachTime => Icons.help_outline,
                },
                size: 20,
                color: selected ? cs.primary : null,
              ),
              onChanged: (v) {
                if (v != null) sync.conflictStrategy = v;
              },
            );
          }),

          // Pending conflicts list (when askEachTime or demo)
          if (sync.pendingConflicts.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange.shade700),
                  const SizedBox(width: 6),
                  Text('${sync.pendingConflicts.length} conflict(s) need attention',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orange.shade700)),
                ],
              ),
            ),
            ...sync.pendingConflicts.map((c) => _ConflictCard(conflict: c, sync: sync)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => sync.resolveAllConflicts(ConflictStrategy.keepNewest),
                      child: const Text('Resolve all: keep newest'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => sync.resolveAllConflicts(ConflictStrategy.keepLocal),
                      child: const Text('Keep all local'),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (sync.conflictStrategy == ConflictStrategy.askEachTime) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text('No pending conflicts — you’ll be asked when one occurs.',
                  style: TextStyle(fontSize: 11, color: cs.outline)),
            ),
          ],

          const Divider(),

          // ── Storage info ──
          _SectionHeader(icon: Icons.info_outline, title: 'Info'),
          ListTile(
            dense: true,
            leading: const Icon(Icons.storage_outlined, size: 20),
            title: const Text('What syncs?'),
            subtitle: const Text('Book metadata, playback position, bookmarks, history. Audio files stay on device.',
                style: TextStyle(fontSize: 12)),
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.lock_outline, size: 20),
            title: const Text('Privacy'),
            subtitle: const Text('Sync uses Supabase Auth + Row Level Security. Data is end-to-end scoped to your account.',
                style: TextStyle(fontSize: 12)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Placeholder mode: no network calls yet. Add supabase_flutter and replace SyncService.signIn/syncNow internals. '
              'All UI and state wiring is already done.',
              style: TextStyle(fontSize: 11, color: cs.outline, fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _doSignIn(SyncService sync) async {
    final ok = await sync.signIn(email: _emailCtrl.text.trim(), password: _passCtrl.text);
    if (!mounted) return;
    if (ok) {
      setState(() => _showLoginForm = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Signed in as ${sync.accountEmail}')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sync.errorMessage ?? 'Sign in failed')));
    }
  }

  Future<void> _confirmSignOut(BuildContext context, SyncService sync) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text('You’ll stay signed out on this device. Sync will pause until you sign in again.\n\n${sync.accountEmail}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (ok == true) {
      await sync.signOut();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Signed out')));
      }
    }
  }

  void _showInfoDialog(BuildContext context, String title, String body) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(body, style: const TextStyle(fontSize: 13))),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Got it'))],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;
  const _SectionHeader({required this.icon, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _ConflictCard extends StatelessWidget {
  final SyncConflict conflict;
  final SyncService sync;
  const _ConflictCard({required this.conflict, required this.sync});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    String fmt(DateTime d) => DateFormat('MMM d, HH:mm').format(d);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.menu_book, size: 16, color: cs.primary),
                const SizedBox(width: 6),
                Expanded(child: Text(conflict.bookTitle, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  tooltip: 'Dismiss',
                  onPressed: () => sync.dismissConflict(conflict.id),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 28, height: 28),
                ),
              ],
            ),
            Text(conflict.field, style: TextStyle(fontSize: 11, color: cs.outline)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _ConflictOption(
                    label: 'Local',
                    value: conflict.localValue,
                    time: fmt(conflict.localTime),
                    color: cs.primaryContainer,
                    onColor: cs.onPrimaryContainer,
                    onTap: () => sync.resolveConflict(conflict.id, keepLocal: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ConflictOption(
                    label: 'Cloud',
                    value: conflict.remoteValue,
                    time: fmt(conflict.remoteTime),
                    color: cs.secondaryContainer,
                    onColor: cs.onSecondaryContainer,
                    onTap: () => sync.resolveConflict(conflict.id, keepLocal: false),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ConflictOption extends StatelessWidget {
  final String label;
  final String value;
  final String time;
  final Color color;
  final Color onColor;
  final VoidCallback onTap;
  const _ConflictOption({
    required this.label,
    required this.value,
    required this.time,
    required this.color,
    required this.onColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: onColor)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: onColor)),
            Text(time, style: TextStyle(fontSize: 10, color: onColor.withValues(alpha: 0.7))),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: onColor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
              child: Text('Use this', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: onColor)),
            ),
          ],
        ),
      ),
    );
  }
}
