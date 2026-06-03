import 'dart:async';

import 'package:flutter/material.dart';

import 'win32_helpers.dart' as win32;

typedef Win32PollingRelease = void Function();

abstract class Win32StateSampler {
  Offset getGlobalCursorPos();
  Rect? getForegroundWindowRect();
  String? getForegroundProcessName();
}

class DefaultWin32StateSampler implements Win32StateSampler {
  const DefaultWin32StateSampler();

  @override
  Offset getGlobalCursorPos() => win32.getGlobalCursorPos();

  @override
  Rect? getForegroundWindowRect() => win32.getForegroundWindowRect();

  @override
  String? getForegroundProcessName() => win32.getForegroundProcessName();
}

class Win32PollingService {
  Win32PollingService({
    Win32StateSampler sampler = const DefaultWin32StateSampler(),
    this.cursorInterval = const Duration(milliseconds: 16),
    this.foregroundWindowRectInterval = const Duration(milliseconds: 50),
    this.foregroundProcessNameInterval = const Duration(seconds: 2),
  }) : _sampler = sampler;

  final Win32StateSampler _sampler;
  final Duration cursorInterval;
  final Duration foregroundWindowRectInterval;
  final Duration foregroundProcessNameInterval;

  final ValueNotifier<Offset> cursorPosition = ValueNotifier(Offset.zero);
  final ValueNotifier<Rect?> foregroundWindowRect = ValueNotifier(null);
  final ValueNotifier<String?> foregroundProcessName = ValueNotifier(null);

  int _cursorConsumers = 0;
  int _foregroundWindowRectConsumers = 0;
  int _foregroundProcessNameConsumers = 0;
  Duration _elapsed = Duration.zero;
  Duration? _lastCursorPoll;
  Duration? _lastForegroundWindowRectPoll;
  Duration? _lastForegroundProcessNamePoll;
  Duration? _activePeriod;
  Timer? _timer;

  Win32PollingRelease retainCursorPolling() {
    final wasInactive = _cursorConsumers == 0;
    _cursorConsumers++;
    if (wasInactive) {
      _pollCursorPosition();
    }
    _updateTimer();
    return _releaseOnce(() {
      _cursorConsumers--;
      _updateTimer();
    });
  }

  Win32PollingRelease retainForegroundWindowRectPolling() {
    final wasInactive = _foregroundWindowRectConsumers == 0;
    _foregroundWindowRectConsumers++;
    if (wasInactive) {
      _pollForegroundWindowRect();
    }
    _updateTimer();
    return _releaseOnce(() {
      _foregroundWindowRectConsumers--;
      _updateTimer();
    });
  }

  Win32PollingRelease retainForegroundProcessNamePolling() {
    final wasInactive = _foregroundProcessNameConsumers == 0;
    _foregroundProcessNameConsumers++;
    if (wasInactive) {
      _pollForegroundProcessName();
    }
    _updateTimer();
    return _releaseOnce(() {
      _foregroundProcessNameConsumers--;
      _updateTimer();
    });
  }

  Win32PollingRelease addCursorPositionListener(VoidCallback listener) {
    cursorPosition.addListener(listener);
    final releasePolling = retainCursorPolling();
    return _releaseOnce(() {
      cursorPosition.removeListener(listener);
      releasePolling();
    });
  }

  Win32PollingRelease addForegroundWindowRectListener(VoidCallback listener) {
    foregroundWindowRect.addListener(listener);
    final releasePolling = retainForegroundWindowRectPolling();
    return _releaseOnce(() {
      foregroundWindowRect.removeListener(listener);
      releasePolling();
    });
  }

  Win32PollingRelease addForegroundProcessNameListener(VoidCallback listener) {
    foregroundProcessName.addListener(listener);
    final releasePolling = retainForegroundProcessNamePolling();
    return _releaseOnce(() {
      foregroundProcessName.removeListener(listener);
      releasePolling();
    });
  }

  Offset refreshCursorPosition() {
    _pollCursorPosition();
    return cursorPosition.value;
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _activePeriod = null;
    cursorPosition.dispose();
    foregroundWindowRect.dispose();
    foregroundProcessName.dispose();
  }

  Win32PollingRelease _releaseOnce(VoidCallback release) {
    var released = false;
    return () {
      if (released) return;
      released = true;
      release();
    };
  }

  void _updateTimer() {
    final nextPeriod = _effectiveTimerPeriod();
    if (nextPeriod == _activePeriod) return;

    _timer?.cancel();
    _timer = null;
    _activePeriod = nextPeriod;

    if (nextPeriod == null) return;
    _timer = Timer.periodic(nextPeriod, (_) {
      _elapsed += nextPeriod;
      _pollDueState();
    });
  }

  Duration? _effectiveTimerPeriod() {
    if (_cursorConsumers > 0) return cursorInterval;
    if (_foregroundWindowRectConsumers > 0) {
      return foregroundWindowRectInterval;
    }
    if (_foregroundProcessNameConsumers > 0) {
      return foregroundProcessNameInterval;
    }
    return null;
  }

  void _pollDueState() {
    if (_cursorConsumers > 0 && _isDue(_lastCursorPoll, cursorInterval)) {
      _pollCursorPosition();
    }
    if (_foregroundWindowRectConsumers > 0 &&
        _isDue(_lastForegroundWindowRectPoll, foregroundWindowRectInterval)) {
      _pollForegroundWindowRect();
    }
    if (_foregroundProcessNameConsumers > 0 &&
        _isDue(_lastForegroundProcessNamePoll, foregroundProcessNameInterval)) {
      _pollForegroundProcessName();
    }
  }

  bool _isDue(Duration? lastPoll, Duration interval) {
    if (lastPoll == null) return true;
    return _elapsed - lastPoll >= interval;
  }

  void _pollCursorPosition() {
    final next = _sampler.getGlobalCursorPos();
    _lastCursorPoll = _elapsed;
    if (cursorPosition.value != next) {
      cursorPosition.value = next;
    }
  }

  void _pollForegroundWindowRect() {
    final next = _sampler.getForegroundWindowRect();
    _lastForegroundWindowRectPoll = _elapsed;
    if (foregroundWindowRect.value != next) {
      foregroundWindowRect.value = next;
    }
  }

  void _pollForegroundProcessName() {
    final next = _sampler.getForegroundProcessName();
    _lastForegroundProcessNamePoll = _elapsed;
    if (foregroundProcessName.value != next) {
      foregroundProcessName.value = next;
    }
  }
}
