String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (h > 0) return '$h:$m:$s';
  return '$m:$s';
}

String formatDurationLong(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h > 0) return '${h}h ${m}m';
  return '${d.inMinutes}m';
}

String formatDateTime(DateTime dt) {
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inDays == 0) {
    if (diff.inHours == 0) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }
  if (diff.inDays == 1) return 'Yesterday';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';
}

String safeBasename(String p) {
  final sep = p.contains('/') ? '/' : (p.contains(r'\') ? r'\' : '/');
  return p.split(sep).last;
}

String titleFromPath(String p) {
  final b = safeBasename(p);
  final dot = b.lastIndexOf('.');
  final name = dot > 0 ? b.substring(0, dot) : b;
  return name.replaceAll('_', ' ').replaceAll('-', ' ').trim();
}

extension DurationX on Duration {
  String get hhmmss => formatDuration(this);
}
