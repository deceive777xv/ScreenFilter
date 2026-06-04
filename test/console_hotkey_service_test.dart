import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_filter_app/models/advanced_config.dart';
import 'package:screen_filter_app/services/console_hotkey_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('screen_filter_app/hotkey');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('registers enabled hotkey preset over the platform channel', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });

    final service = ConsoleHotkeyService(onPressed: () {});

    final registered = await service.apply(
      const ConsoleHotkeyConfig(enabled: true, presetId: 'ctrl_alt_s'),
    );

    expect(registered, isTrue);
    expect(calls.single.method, 'registerHotkey');
    expect(calls.single.arguments, {
      'modifiers': 0x0001 | 0x0002,
      'keyCode': 0x53,
    });
  });

  test('unregisters when hotkey is disabled', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });

    final service = ConsoleHotkeyService(onPressed: () {});

    final registered = await service.apply(
      const ConsoleHotkeyConfig(enabled: false),
    );

    expect(registered, isFalse);
    expect(calls.single.method, 'unregisterHotkey');
  });
}
