import 'package:flutter_test/flutter_test.dart';
import 'package:crisperplayer/utils/format.dart';

void main() {
  group('formatDuration', () {
    test('zero', () => expect(formatDuration(Duration.zero), '00:00'));
    test('seconds',
        () => expect(formatDuration(const Duration(seconds: 5)), '00:05'));
    test(
        'minutes',
        () => expect(
            formatDuration(const Duration(minutes: 2, seconds: 3)), '02:03'));
    test(
        'hours',
        () => expect(
            formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)),
            '1:02:03'));
  });
  group('titleFromPath', () {
    test('m4b basename',
        () => expect(titleFromPath('/books/My Book.m4b'), 'My Book'));
    test('underscores',
        () => expect(titleFromPath('/tmp/my_book-file.m4b'), 'my book file'));
  });
  group('formatDateTime', () {
    test('recent', () {
      final now = DateTime.now();
      expect(formatDateTime(now.subtract(const Duration(minutes: 2))),
          contains('m ago'));
    });
  });
}
