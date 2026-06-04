import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:screen_filter_app/models/advanced_config.dart';
import 'package:screen_filter_app/models/overlay_component.dart';
import 'package:screen_filter_app/services/settings_service.dart';

void main() {
  test('AppConfig preserves automation enabled flag in JSON snapshots', () {
    final config = AppConfig(
      automationEnabled: true,
      consoleHotkey: const ConsoleHotkeyConfig(
        enabled: true,
        presetId: 'ctrl_alt_s',
      ),
      automationRules: [
        AutomationRule(processName: 'chrome.exe', presetName: '夜间'),
      ],
    );

    final decoded = AppConfig.fromJson(config.toJson());

    expect(decoded.automationEnabled, isTrue);
    expect(decoded.consoleHotkey.enabled, isTrue);
    expect(decoded.consoleHotkey.presetId, 'ctrl_alt_s');
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
        consoleHotkey: const ConsoleHotkeyConfig(
          enabled: true,
          presetId: 'alt_f12',
        ),
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
      expect(settings.getConsoleHotkeyConfig().enabled, isTrue);
      expect(settings.getConsoleHotkeyConfig().presetId, 'alt_f12');
      expect(settings.getAutomationRules().single.processName, 'code.exe');
      expect(settings.getFocusModeConfig().enabled, isTrue);
      expect(settings.getFocusModeConfig().dimOpacity, 0.7);
    },
  );

  test('falls back when recent color preferences are corrupted', () async {
    SharedPreferences.setMockInitialValues({
      'filter_recent_colors': ['not-a-color'],
    });
    final settings = await SettingsService.init();

    final colors = settings.getRecentColors();

    expect(colors, contains(const Color(0xFFFFB300)));
    expect(colors.length, 5);
  });

  test('falls back when persisted advanced JSON is corrupted', () async {
    SharedPreferences.setMockInitialValues({
      'overlay_clock': '{bad-json',
      'advanced_focus_mode': '{bad-json',
      'advanced_spotlight': '[]',
      'advanced_automation_rules': '{not-a-list',
      'advanced_region_mask': 'null',
    });
    final settings = await SettingsService.init();

    expect(
      settings.getOverlayComponent(OverlayType.clock).type,
      OverlayType.clock,
    );
    expect(settings.getFocusModeConfig().enabled, isFalse);
    expect(settings.getSpotlightConfig().enabled, isFalse);
    expect(settings.getAutomationRules(), isEmpty);
    expect(settings.getRegionMaskConfig().enabled, isFalse);
  });

  test(
    'AppConfig falls back when imported nested sections have wrong types',
    () {
      final decoded = AppConfig.fromJson({
        'settings': {
          'baseColor': 'not-an-int',
          'recentColors': ['bad-color'],
          'startupEnabled': 'yes',
        },
        'focusMode': [],
        'spotlight': 'bad',
        'regionMask': null,
        'automationRules': ['bad-rule'],
      });

      expect(decoded.baseColor, Colors.transparent);
      expect(decoded.recentColors, isEmpty);
      expect(decoded.startupEnabled, isFalse);
      expect(decoded.focusMode.enabled, isFalse);
      expect(decoded.spotlight.enabled, isFalse);
      expect(decoded.regionMask.enabled, isFalse);
      expect(decoded.automationRules, isEmpty);
    },
  );
}
