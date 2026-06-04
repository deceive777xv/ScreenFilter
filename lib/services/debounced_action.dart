import 'dart:async';

/// Runs the latest scheduled callback after a quiet period.
class DebouncedAction {
  DebouncedAction({required this.delay});

  final Duration delay;
  Timer? _timer;
  void Function()? _pendingAction;

  void schedule(void Function() action) {
    _pendingAction = action;
    _timer?.cancel();
    _timer = Timer(delay, _runPending);
  }

  void flush() {
    if (_pendingAction == null) return;
    _timer?.cancel();
    _timer = null;
    _runPending();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _pendingAction = null;
  }

  void dispose() {
    cancel();
  }

  void _runPending() {
    final action = _pendingAction;
    _pendingAction = null;
    _timer = null;
    action?.call();
  }
}
