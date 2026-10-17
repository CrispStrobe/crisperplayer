import 'dart:async';

Future<T> measure<T>(String label, FutureOr<T> Function() fn) async {
  final sw = Stopwatch()..start();
  final r = await fn();
  sw.stop();
  // ignore: avoid_print
  print('$label: ${sw.elapsedMilliseconds} ms');
  return r;
}
