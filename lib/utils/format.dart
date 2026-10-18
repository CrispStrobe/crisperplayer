String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (h > 0) return '$h:$m:$s';
  return '$m:$s';
}

String formatSpokenDuration(Duration duration) {
  final seconds = duration.isNegative ? 0 : duration.inSeconds;
  final hours = seconds ~/ 3600;
  final minutes = (seconds ~/ 60) % 60;
  final rest = seconds % 60;
  String unit(int count, String name) => '$count $name${count == 1 ? '' : 's'}';
  return [
    if (hours > 0) unit(hours, 'hour'),
    if (minutes > 0) unit(minutes, 'minute'),
    if (rest > 0 || seconds == 0) unit(rest, 'second'),
  ].join(', ');
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

/// Absolute seconds, MM:SS or HH:MM:SS, optionally with milliseconds.
Duration parseTimecode(String text) {
  final value = text.trim();
  if (!RegExp(r'^\d+(?::\d{1,2}){0,2}(?:\.\d{1,3})?$').hasMatch(value)) {
    throw const FormatException('Use seconds, MM:SS or HH:MM:SS.');
  }
  final parts = value.split(':');
  var seconds = 0.0;
  for (var index = 0; index < parts.length; index++) {
    final part = double.parse(parts[index]);
    if (!part.isFinite || (index > 0 && part >= 60)) {
      throw const FormatException('Minutes and seconds must be below 60.');
    }
    seconds = seconds * 60 + part;
  }
  if (seconds > 315360000) throw const FormatException('Time is too large.');
  return Duration(milliseconds: (seconds * 1000).round());
}
