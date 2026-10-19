/// Progress carries a vector clock, never a wall-clock timestamp. Concurrent
/// listening is surfaced for a decision rather than choosing the larger offset.
class ProgressRecord {
  final Map<String, int> clock;
  final int index, positionMs;
  final List<int> durations;
  const ProgressRecord(this.clock, this.index, this.positionMs, this.durations);
  factory ProgressRecord.fromJson(Map<String, dynamic> row) {
    final clock = Map<String, int>.from(row['clock'] as Map);
    final durations = (row['durations'] as List).cast<int>();
    final index = row['index'] as int, position = row['positionMs'] as int;
    if (clock.isEmpty ||
        clock.length > 100 ||
        clock.values.any((v) => v < 1 || v > 1 << 52) ||
        durations.isEmpty ||
        durations.length > 10000 ||
        durations.any((v) => v <= 0) ||
        index < 0 ||
        index >= durations.length ||
        position < 0 ||
        position > durations[index]) {
      throw const FormatException('Invalid progress record.');
    }
    return ProgressRecord(clock, index, position, durations);
  }
  Map<String, Object?> toJson() => {
    'clock': clock,
    'index': index,
    'positionMs': positionMs,
    'durations': durations,
  };
  bool dominates(ProgressRecord other) =>
      other.clock.entries.every((e) => (clock[e.key] ?? 0) >= e.value) &&
      clock.entries.any((e) => e.value > (other.clock[e.key] ?? 0));
  bool sameClock(ProgressRecord other) =>
      clock.length == other.clock.length &&
      clock.entries.every((e) => other.clock[e.key] == e.value);
  bool samePosition(ProgressRecord other) =>
      index == other.index && positionMs == other.positionMs;
  ProgressRecord change(
    String device,
    int nextIndex,
    int nextPosition,
    List<int> nextDurations, [
    ProgressRecord? observed,
  ]) {
    final merged = {...clock};
    for (final e in observed?.clock.entries ?? <MapEntry<String, int>>[]) {
      if ((merged[e.key] ?? 0) < e.value) merged[e.key] = e.value;
    }
    merged[device] = (merged[device] ?? 0) + 1;
    return ProgressRecord(merged, nextIndex, nextPosition, nextDurations);
  }
}
