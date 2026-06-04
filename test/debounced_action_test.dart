import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_filter_app/services/debounced_action.dart';
import 'package:screen_filter_app/services/keyed_debounced_action.dart';

void main() {
  test('runs only the latest scheduled action after the debounce delay', () {
    fakeAsync((async) {
      final calls = <String>[];
      final action = DebouncedAction(delay: const Duration(milliseconds: 50));

      action.schedule(() => calls.add('first'));
      async.elapse(const Duration(milliseconds: 25));
      action.schedule(() => calls.add('second'));
      async.elapse(const Duration(milliseconds: 49));

      expect(calls, isEmpty);

      async.elapse(const Duration(milliseconds: 1));

      expect(calls, ['second']);
      action.dispose();
    });
  });

  test('flush runs pending work immediately and prevents delayed reruns', () {
    fakeAsync((async) {
      var calls = 0;
      final action = DebouncedAction(delay: const Duration(milliseconds: 50));

      action.schedule(() => calls++);
      action.flush();
      async.elapse(const Duration(milliseconds: 100));

      expect(calls, 1);
      action.dispose();
    });
  });

  test('keyed debounce keeps latest action for each independent key', () {
    fakeAsync((async) {
      final calls = <String>[];
      final action = KeyedDebouncedAction<String>(
        delay: const Duration(milliseconds: 50),
      );

      action.schedule('overlay:clock', () => calls.add('clock-1'));
      action.schedule('advanced:focus', () => calls.add('focus'));
      action.schedule('overlay:clock', () => calls.add('clock-2'));
      async.elapse(const Duration(milliseconds: 49));

      expect(calls, isEmpty);

      async.elapse(const Duration(milliseconds: 1));

      expect(calls, hasLength(2));
      expect(calls, containsAll(['focus', 'clock-2']));
      expect(calls, isNot(contains('clock-1')));
      action.dispose();
    });
  });
}
