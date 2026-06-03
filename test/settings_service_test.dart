import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_filter_app/models/advanced_config.dart';
import 'package:screen_filter_app/services/settings_service.dart';

void main() {
  test('AppConfig preserves automation enabled flag in JSON snapshots', () {
    final config = AppConfig(
      automationEnabled: true,
      automationRules: [
        AutomationRule(processName: 'chrome.exe', presetName: '夜间'),
      ],
    );

    final decoded = AppConfig.fromJson(config.toJson());

    expect(decoded.automationEnabled, isTrue);
    expect(decoded.automationRules.single.processName, 'chrome.exe');
  });

  test(
    'saveAppConfig persists automation enabled and advanced settings',
    () async {
      SharedPreferences.setMockInitialValues({});
      final settings = await SettingsService.init();
      final config = AppConfig(
        brightness: -0.2,
        alpha: 0.4,
        baseColor: Colors.black,
        activePreset: '夜间',
        automationEnabled: true,
        automationRules: [
          AutomationRule(processName: 'code.exe', presetName: '护眼'),
        ],
        focusMode: FocusModeConfig(enabled: true, dimOpacity: 0.7),
      );

      await settings.saveAppConfig(config);

      expect(settings.getBrightness(), -0.2);
      expect(settings.getAlpha(), 0.4);
      expect(settings.getBaseColor(), Colors.black);
      expect(settings.getActivePreset(), '夜间');
      expect(settings.getAutomationEnabled(), isTrue);
      expect(settings.getAutomationRules().single.processName, 'code.exe');
      expect(settings.getFocusModeConfig().enabled, isTrue);
      expect(settings.getFocusModeConfig().dimOpacity, 0.7);
    },
  );
}
