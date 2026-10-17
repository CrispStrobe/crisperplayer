import 'package:flutter_test/flutter_test.dart';
import 'package:crisperplayer/utils/format.dart';

void main() {
  test('bookPosition calculation', () {
    // book with 3 files: 10min each, currently at file index 1 offset 2min
    final fileDurations = [const Duration(minutes: 10), const Duration(minutes: 10), const Duration(minutes: 10)];
    final currentIndex = 1;
    final positionInFile = const Duration(minutes: 2);
    Duration bookOffset = Duration.zero;
    for (int i=0;i<currentIndex;i++) bookOffset += fileDurations[i];
    final bookPos = bookOffset + positionInFile;
    expect(bookPos, const Duration(minutes: 12));
    expect(formatDuration(bookPos), '12:00');
  });

  test('progress clamp', () {
    final total = const Duration(hours: 10);
    final bookPos = const Duration(hours: 11);
    final progress = (bookPos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    expect(progress, 1.0);
  });

  test('sleep timer math', () {
    var remaining = const Duration(minutes: 15);
    remaining -= const Duration(seconds: 1);
    expect(remaining, const Duration(minutes: 14, seconds: 59));
  });
}
