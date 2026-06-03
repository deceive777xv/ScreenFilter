import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_filter_app/services/win32_polling_service.dart';

void main() {
  test('does not poll until a consumer subscribes', () {
    fakeAsync((async) {
      final sampler = _FakeWin32StateSampler();
      final service = Win32PollingService(
        sampler: sampler,
        cursorInterval: const Duration(milliseconds: 10),
      );

      async.elapse(const Duration(milliseconds: 50));

      expect(sampler.cursorCalls, 0);

      final release = service.retainCursorPolling();
      expect(sampler.cursorCalls, 1);

      async.elapse(const Duration(milliseconds: 10));
      expect(sampler.cursorCalls, 2);

      release();
      async.elapse(const Duration(milliseconds: 50));
      expect(sampler.cursorCalls, 2);

      service.dispose();
    });
  });

  test('shares cursor polling across multiple listeners', () {
    fakeAsync((async) {
      final sampler = _FakeWin32StateSampler();
      final service = Win32PollingService(
        sampler: sampler,
        cursorInterval: const Duration(milliseconds: 10),
      );
      var firstNotifications = 0;
      var secondNotifications = 0;

      final releaseFirst = service.addCursorPositionListener(() {
        firstNotifications++;
      });
      final releaseSecond = service.addCursorPositionListener(() {
        secondNotifications++;
      });

      expect(sampler.cursorCalls, 1);
      expect(firstNotifications, 1);
      expect(secondNotifications, 0);

      async.elapse(const Duration(milliseconds: 10));
      expect(sampler.cursorCalls, 2);
      expect(firstNotifications, 2);
      expect(secondNotifications, 1);

      releaseFirst();
      releaseSecond();
      service.dispose();
    });
  });

  test('polls slower Win32 state on the shared scheduler', () {
    fakeAsync((async) {
      final sampler = _FakeWin32StateSampler();
      final service = Win32PollingService(
        sampler: sampler,
        cursorInterval: const Duration(milliseconds: 10),
        foregroundWindowRectInterval: const Duration(milliseconds: 30),
        foregroundProcessNameInterval: const Duration(milliseconds: 50),
      );

      final releaseCursor = service.retainCursorPolling();
      final releaseRect = service.retainForegroundWindowRectPolling();
      final releaseProcess = service.retainForegroundProcessNamePolling();

      expect(sampler.cursorCalls, 1);
      expect(sampler.rectCalls, 1);
      expect(sampler.processCalls, 1);

      async.elapse(const Duration(milliseconds: 20));
      expect(sampler.cursorCalls, 3);
      expect(sampler.rectCalls, 1);
      expect(sampler.processCalls, 1);

      async.elapse(const Duration(milliseconds: 10));
      expect(sampler.cursorCalls, 4);
      expect(sampler.rectCalls, 2);
      expect(sampler.processCalls, 1);

      async.elapse(const Duration(milliseconds: 20));
      expect(sampler.cursorCalls, 6);
      expect(sampler.rectCalls, 2);
      expect(sampler.processCalls, 2);

      releaseCursor();
      releaseRect();
      releaseProcess();
      service.dispose();
    });
  });
}

class _FakeWin32StateSampler implements Win32StateSampler {
  int cursorCalls = 0;
  int rectCalls = 0;
  int processCalls = 0;

  @override
  Offset getGlobalCursorPos() {
    cursorCalls++;
    return Offset(cursorCalls.toDouble(), cursorCalls.toDouble());
  }

  @override
  Rect? getForegroundWindowRect() {
    rectCalls++;
    return Rect.fromLTWH(rectCalls.toDouble(), 0, 100, 100);
  }

  @override
  String? getForegroundProcessName() {
    processCalls++;
    return 'process_$processCalls.exe';
  }
}
