import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/advanced_config.dart';

const int _modAlt = 0x0001;
const int _modControl = 0x0002;
const int _modShift = 0x0004;

class ConsoleHotkeyPreset {
  final String id;
  final String label;
  final int modifiers;
  final int keyCode;

  const ConsoleHotkeyPreset({
    required this.id,
    required this.label,
    required this.modifiers,
    required this.keyCode,
  });
}

const List<ConsoleHotkeyPreset> kConsoleHotkeyPresets = [
  ConsoleHotkeyPreset(
    id: 'ctrl_alt_f',
    label: 'Ctrl + Alt + F',
    modifiers: _modControl | _modAlt,
    keyCode: 0x46,
  ),
  ConsoleHotkeyPreset(
    id: 'ctrl_alt_s',
    label: 'Ctrl + Alt + S',
    modifiers: _modControl | _modAlt,
    keyCode: 0x53,
  ),
  ConsoleHotkeyPreset(
    id: 'ctrl_shift_f',
    label: 'Ctrl + Shift + F',
    modifiers: _modControl | _modShift,
    keyCode: 0x46,
  ),
  ConsoleHotkeyPreset(
    id: 'alt_f12',
    label: 'Alt + F12',
    modifiers: _modAlt,
    keyCode: 0x7B,
  ),
];

ConsoleHotkeyPreset consoleHotkeyPresetById(String id) {
  return kConsoleHotkeyPresets.firstWhere(
    (preset) => preset.id == id,
    orElse: () => kConsoleHotkeyPresets.first,
  );
}

class ConsoleHotkeyService {
  ConsoleHotkeyService({required VoidCallback onPressed})
    : _onPressed = onPressed {
    _channel.setMethodCallHandler(_handlePlatformCall);
  }

  static const MethodChannel _channel = MethodChannel(
    'screen_filter_app/hotkey',
  );

  final VoidCallback _onPressed;

  Future<bool> apply(ConsoleHotkeyConfig config) async {
    if (!config.enabled) {
      await _unregister();
      return false;
    }

    final preset = consoleHotkeyPresetById(config.presetId);
    try {
      return await _channel.invokeMethod<bool>('registerHotkey', {
            'modifiers': preset.modifiers,
            'keyCode': preset.keyCode,
          }) ??
          false;
    } catch (error) {
      debugPrint('Register hotkey failed: $error');
      return false;
    }
  }

  Future<void> dispose() async {
    await _unregister();
    _channel.setMethodCallHandler(null);
  }

  Future<void> _unregister() async {
    try {
      await _channel.invokeMethod<bool>('unregisterHotkey');
    } catch (error) {
      debugPrint('Unregister hotkey failed: $error');
    }
  }

  Future<void> _handlePlatformCall(MethodCall call) async {
    if (call.method == 'hotkeyPressed') {
      _onPressed();
    }
  }
}
