import 'package:crisper_audio/src/source_clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('read-ahead never advances presented source position', () {
    final clock = SourceClock();
    clock.append(100, 200);
    clock.append(200, 400);
    expect(clock.presented(0), 0);
    expect(clock.presented(50), 100);
    expect(clock.presented(100), 200);
    expect(clock.pendingSpans, 1);
    expect(clock.presented(199), 398);
    expect(clock.presented(200), 400);
    expect(clock.pendingSpans, 0);
  });
  test('noninteger tempo and exact final trim map monotonically', () {
    final clock = SourceClock();
    clock.append(3, 4);
    clock.append(7, 10);
    expect(
      [for (var i = 0; i <= 7; i++) clock.presented(i)],
      [0, 1, 2, 4, 5, 7, 8, 10],
    );
  });
  test('seek reset discards old spans and clock rejects invalid output', () {
    final clock = SourceClock();
    clock.append(100, 50);
    clock.presented(100);
    expect(() => clock.presented(99), throwsStateError);
    clock.reset();
    expect(clock.presented(0), 0);
    clock.append(10, 30);
    expect(clock.presented(10), 30);
    expect(() => clock.presented(11), throwsStateError);
  });
}
