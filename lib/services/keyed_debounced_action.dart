import 'dart:async';

/// Debounces multiple independent actions on one shared quiet period.
///
/// Scheduling the same key replaces only that key's pending work, while other
/// keys remain queued for the next flush.
class KeyedDebouncedAction<K> {
  KeyedDebouncedAction({required this.delay});

  final Duration delay;
  final Map<K, void Function()> _pendingActions = {};
  Timer? _timer;

  void schedule(K key, void Function() action) {
    _pendingActions[key] = action;
    _timer?.cancel();
    _timer = Timer(delay, _runPending);
  }

  void flush() {
    if (_pendingActions.isEmpty) return;
    _timer?.cancel();
    _timer = null;
    _runPending();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _pendingActions.clear();
  }

  void dispose() {
    cancel();
  }

  void _runPending() {
    final actions = List<void Function()>.from(_pendingActions.values);
    _pendingActions.clear();
    _timer = null;
    for (final action in actions) {
      action();
    }
  }
}
