import 'package:crisperplayer/services/audio/played_range_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late PlayedRangeRecorder recorder;
  setUp(() => recorder = PlayedRangeRecorder());

  void sample(
    int position,
    int time, {
    String book = 'a',
    String file = 'a.mp3',
    double speed = 1,
  }) {
    recorder.sample(
      bookId: book,
      filePath: file,
      positionMs: position,
      observedAtMs: time,
      speed: speed,
    );
  }

  test(
    'continuous decoded playback coalesces while seek gaps remain absent',
    () {
      sample(0, 0);
      sample(1000, 1000);
      sample(2000, 2000);
      recorder.reset();
      sample(60000, 2000);
      sample(63000, 5000);

      expect(recorder.pending, hasLength(2));
      expect(recorder.pending.map((r) => (r.startMs, r.endMs)), [
        (0, 2000),
        (60000, 63000),
      ]);
    },
  );

  test(
    'unannounced forward jumps and backward clock changes provide no coverage',
    () {
      sample(0, 1000);
      sample(30000, 2000);
      expect(recorder.pending, isEmpty);
      sample(31000, 3000);
      sample(32000, 2500);
      expect(recorder.pending.map((r) => (r.startMs, r.endMs)), [
        (30000, 31000),
      ]);
    },
  );

  test('speed is included in the continuity check', () {
    sample(0, 0, speed: 3);
    sample(6000, 2000, speed: 3);
    expect(recorder.pending.single.endMs, 6000);
    sample(12000, 3000, speed: 1);
    expect(recorder.pending.single.endMs, 6000);
  });

  test('file and book transitions cannot bridge unrelated audio', () {
    sample(50000, 0);
    sample(51000, 1000);
    sample(100000, 2000, file: 'b.mp3');
    sample(101000, 3000, file: 'b.mp3');
    sample(200000, 4000, book: 'b', file: 'b.mp3');
    sample(201000, 5000, book: 'b', file: 'b.mp3');
    expect(
      recorder.pending.map((r) => (r.bookId, r.filePath, r.startMs, r.endMs)),
      [
        ('a', 'a.mp3', 50000, 51000),
        ('a', 'b.mp3', 100000, 101000),
        ('b', 'b.mp3', 200000, 201000),
      ],
    );
  });

  test('backward seeks start new ranges rather than proving unheard audio', () {
    sample(10000, 0);
    sample(11000, 1000);
    sample(2000, 2000);
    sample(3000, 3000);
    expect(recorder.pending.map((r) => (r.startMs, r.endMs)), [
      (10000, 11000),
      (2000, 3000),
    ]);
  });

  test('acknowledging an in-flight save keeps newly extended coverage', () {
    sample(0, 0);
    sample(1000, 1000);
    final saving = recorder.pending.single;
    sample(2000, 2000);
    recorder.acknowledge(saving);
    expect(recorder.pending.single.endMs, 2000);
    recorder.acknowledge(recorder.pending.single);
    expect(recorder.pending, isEmpty);
  });

  test('unsaved ranges remain bounded when storage is unavailable', () {
    for (var i = 0; i < 201; i++) {
      recorder.reset();
      sample(i * 10000, i * 1000);
      sample(i * 10000 + 500, i * 1000 + 500);
    }
    expect(recorder.pending, hasLength(200));
    expect(recorder.pending.first.startMs, 10000);
    expect(recorder.pending.last.endMs, 2000500);
  });
}
