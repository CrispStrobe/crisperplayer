/// Immutable timestamped playback evidence or an explicit player action.
/// All timestamps are UTC epoch milliseconds. The captured offset preserves
/// the local clock used at the time, independently of today's time zone.
class ListeningJournalEntry {
  static const kinds = {
    'played',
    'play',
    'pause',
    'stop',
    'seek',
    'complete',
    'interruption',
    'open',
    'close',
  };
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  final String id;
  final String bookId;
  final String kind;
  final String bookTitle;
  final String? chapterTitle;
  final String filePath;
  final int startMs;
  final int endMs;
  final String? targetFilePath;
  final int? targetPositionMs;
  final int startedAtMs;
  final int endedAtMs;
  final int utcOffsetMinutes;
  final double speed;
  final String? reason;

  const ListeningJournalEntry({
    required this.id,
    required this.bookId,
    required this.kind,
    this.bookTitle = '',
    this.chapterTitle,
    required this.filePath,
    required this.startMs,
    required this.endMs,
    this.targetFilePath,
    this.targetPositionMs,
    required this.startedAtMs,
    required this.endedAtMs,
    required this.utcOffsetMinutes,
    this.speed = 1,
    this.reason,
  });

  bool get isPlayed => kind == 'played';
  int get mediaDurationMs => isPlayed ? endMs - startMs : 0;
  int get elapsedMs => endedAtMs - startedAtMs;

  Map<String, Object?> toJson() => {
    'id': id,
    'bookId': bookId,
    'kind': kind,
    'bookTitle': bookTitle,
    'chapterTitle': chapterTitle,
    'filePath': filePath,
    'startMs': startMs,
    'endMs': endMs,
    'targetFilePath': targetFilePath,
    'targetPositionMs': targetPositionMs,
    'startedAtMs': startedAtMs,
    'endedAtMs': endedAtMs,
    'utcOffsetMinutes': utcOffsetMinutes,
    'speed': speed,
    'reason': reason,
  };

  factory ListeningJournalEntry.fromJson(Map<String, dynamic> json) {
    String text(String key, {int max = 32768}) {
      final value = json[key];
      if (value is! String || value.isEmpty || value.length > max) {
        throw FormatException('Invalid journal $key');
      }
      return value;
    }

    int integer(String key, {int min = 0, int max = 8640000000000000}) {
      final value = json[key];
      if (value is! int || value < min || value > max) {
        throw FormatException('Invalid journal $key');
      }
      return value;
    }

    String? optionalText(String key, int max) {
      final value = json[key];
      if (value == null) return null;
      if (value is! String || value.length > max) {
        throw FormatException('Invalid journal $key');
      }
      return value;
    }

    final id = text('id', max: 36).toLowerCase();
    if (!_uuid.hasMatch(id)) {
      throw const FormatException('Invalid journal UUID');
    }
    final bookId = text('bookId', max: 1024);
    final kind = text('kind', max: 32);
    if (!kinds.contains(kind)) {
      throw const FormatException('Invalid journal kind');
    }
    final filePath = text('filePath');
    final startMs = integer('startMs');
    final endMs = integer('endMs');
    final startedAtMs = integer('startedAtMs');
    final endedAtMs = integer('endedAtMs');
    final offset = integer('utcOffsetMinutes', min: -840, max: 840);
    final rawSpeed = json['speed'];
    if (rawSpeed is! num ||
        !rawSpeed.isFinite ||
        rawSpeed < 0.5 ||
        rawSpeed > 3) {
      throw const FormatException('Invalid journal speed');
    }
    if (endedAtMs < startedAtMs ||
        (kind == 'played' && endMs <= startMs) ||
        (kind != 'played' && (endMs != startMs || endedAtMs != startedAtMs))) {
      throw const FormatException('Invalid journal interval');
    }
    final targetPath = optionalText('targetFilePath', 32768);
    final targetPosition = json['targetPositionMs'];
    if (kind == 'seek') {
      if (targetPath == null ||
          targetPath.isEmpty ||
          targetPosition is! int ||
          targetPosition < 0 ||
          targetPosition > 8640000000000000) {
        throw const FormatException(
          'A journal seek requires its exact destination',
        );
      }
    } else if (targetPath != null || targetPosition != null) {
      throw const FormatException('Only journal seeks have a destination');
    }
    final title = optionalText('bookTitle', 4096);
    return ListeningJournalEntry(
      id: id,
      bookId: bookId,
      kind: kind,
      bookTitle: title == null || title.isEmpty ? bookId : title,
      chapterTitle: optionalText('chapterTitle', 4096),
      filePath: filePath,
      startMs: startMs,
      endMs: endMs,
      targetFilePath: targetPath,
      targetPositionMs: targetPosition as int?,
      startedAtMs: startedAtMs,
      endedAtMs: endedAtMs,
      utcOffsetMinutes: offset,
      speed: rawSpeed.toDouble(),
      reason: optionalText('reason', 512),
    );
  }

  bool samePlayedOrigin(ListeningJournalEntry other) =>
      isPlayed &&
      other.isPlayed &&
      id == other.id &&
      bookId == other.bookId &&
      filePath == other.filePath &&
      startMs == other.startMs &&
      startedAtMs == other.startedAtMs &&
      utcOffsetMinutes == other.utcOffsetMinutes &&
      speed == other.speed &&
      reason == other.reason;

  bool sameEvent(ListeningJournalEntry other) =>
      !isPlayed &&
      !other.isPlayed &&
      id == other.id &&
      bookId == other.bookId &&
      kind == other.kind &&
      filePath == other.filePath &&
      startMs == other.startMs &&
      endMs == other.endMs &&
      targetFilePath == other.targetFilePath &&
      targetPositionMs == other.targetPositionMs &&
      startedAtMs == other.startedAtMs &&
      endedAtMs == other.endedAtMs &&
      utcOffsetMinutes == other.utcOffsetMinutes &&
      speed == other.speed &&
      reason == other.reason;
}

/// An exact source location or half-open source range whose recorded plays
/// should be shown. This does not establish that a file is still available or
/// that the location can currently be opened by the player.
final class JournalPassageFilter {
  static const _maxPositionMs = 8640000000000000;

  final String bookId;
  final String filePath;
  final int startMs;
  final int? endMs;

  const JournalPassageFilter._({
    required this.bookId,
    required this.filePath,
    required this.startMs,
    this.endMs,
  });

  factory JournalPassageFilter.point({
    required String bookId,
    required String filePath,
    required int positionMs,
  }) {
    _validateSource(bookId, filePath);
    _validatePosition(positionMs);
    return JournalPassageFilter._(
      bookId: bookId,
      filePath: filePath,
      startMs: positionMs,
    );
  }

  factory JournalPassageFilter.range({
    required String bookId,
    required String filePath,
    required int startMs,
    required int endMs,
  }) {
    _validateSource(bookId, filePath);
    _validatePosition(startMs);
    _validatePosition(endMs);
    if (endMs <= startMs) {
      throw ArgumentError(
        'A journal passage range must have a positive length',
      );
    }
    return JournalPassageFilter._(
      bookId: bookId,
      filePath: filePath,
      startMs: startMs,
      endMs: endMs,
    );
  }

  static void _validateSource(String bookId, String filePath) {
    if (bookId.isEmpty ||
        bookId.length > 1024 ||
        filePath.isEmpty ||
        filePath.length > 32768) {
      throw ArgumentError('Invalid journal passage source');
    }
  }

  static void _validatePosition(int value) {
    if (value < 0 || value > _maxPositionMs) {
      throw ArgumentError('Invalid journal passage position');
    }
  }

  bool get isPoint => endMs == null;
  int? get positionMs => isPoint ? startMs : null;

  Map<String, Object> toJson() => {
    'bookId': bookId,
    'filePath': filePath,
    if (isPoint) 'positionMs': startMs,
    if (!isPoint) 'startMs': startMs,
    if (!isPoint) 'endMs': endMs!,
  };

  factory JournalPassageFilter.fromJson(Map<String, dynamic> json) {
    final book = json['bookId'];
    final path = json['filePath'];
    final hasPoint = json.containsKey('positionMs');
    final hasRange = json.containsKey('startMs') || json.containsKey('endMs');
    if (book is! String || path is! String || hasPoint == hasRange) {
      throw const FormatException('Invalid journal passage filter');
    }
    try {
      if (hasPoint) {
        final position = json['positionMs'];
        if (position is! int) throw const FormatException();
        return JournalPassageFilter.point(
          bookId: book,
          filePath: path,
          positionMs: position,
        );
      }
      final start = json['startMs'];
      final end = json['endMs'];
      if (start is! int || end is! int) throw const FormatException();
      return JournalPassageFilter.range(
        bookId: book,
        filePath: path,
        startMs: start,
        endMs: end,
      );
    } on ArgumentError {
      throw const FormatException('Invalid journal passage filter');
    } on FormatException {
      throw const FormatException('Invalid journal passage filter');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is JournalPassageFilter &&
      bookId == other.bookId &&
      filePath == other.filePath &&
      startMs == other.startMs &&
      endMs == other.endMs;

  @override
  int get hashCode => Object.hash(bookId, filePath, startMs, endMs);
}

class JournalPage {
  final List<ListeningJournalEntry> entries;
  final String? nextCursor;
  JournalPage({required List<ListeningJournalEntry> entries, this.nextCursor})
    : entries = List.unmodifiable(entries);
  bool get hasMore => nextCursor != null;
  Map<String, Object?> toJson() => {
    'entries': entries.map((entry) => entry.toJson()).toList(),
    'nextCursor': nextCursor,
  };
}
