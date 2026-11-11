import 'dart:async';

/// Coalesces transfer progress without delaying state transitions.
/// Byte counters are updated by the caller before scheduling a notification.
class ProgressNotifications {
  final void Function() notify;
  final Duration interval;
  Timer? _pending;
  bool _disposed = false;

  ProgressNotifications(
    this.notify, {
    this.interval = const Duration(milliseconds: 100),
  });

  void schedule() {
    if (_disposed) return;
    _pending ??= Timer(interval, flush);
  }

  /// Publish phase changes immediately and absorb any pending progress update.
  void flush() {
    _pending?.cancel();
    _pending = null;
    if (!_disposed) notify();
  }

  void dispose() {
    _disposed = true;
    _pending?.cancel();
    _pending = null;
  }
}
