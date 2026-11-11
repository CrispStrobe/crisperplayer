import 'package:crisperplayer/services/server/progress_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('fast transfer updates coalesce and publish the latest bytes', (
    tester,
  ) async {
    var bytes = 0;
    final observed = <int>[];
    final updates = ProgressNotifications(() => observed.add(bytes));
    addTearDown(updates.dispose);
    for (var i = 0; i < 1000; i++) {
      bytes += 256 * 1024;
      updates.schedule();
    }
    expect(observed, isEmpty);
    await tester.pump(const Duration(milliseconds: 100));
    expect(observed, [bytes]);
    bytes++;
    updates.schedule();
    await tester.pump(const Duration(milliseconds: 100));
    expect(observed, [bytes - 1, bytes]);
  });

  testWidgets('phase changes publish immediately without a stale timer', (
    tester,
  ) async {
    var phase = 'downloading';
    final observed = <String>[];
    final updates = ProgressNotifications(() => observed.add(phase));
    addTearDown(updates.dispose);
    updates.schedule();
    phase = 'importing';
    updates.flush();
    expect(observed, ['importing']);
    await tester.pump(const Duration(seconds: 1));
    expect(observed, ['importing']);
  });

  testWidgets('disposal cancels progress and ignores later notifications', (
    tester,
  ) async {
    var count = 0;
    final updates = ProgressNotifications(() => count++);
    updates.schedule();
    updates.dispose();
    updates.schedule();
    updates.flush();
    await tester.pump(const Duration(seconds: 1));
    expect(count, 0);
  });
}
