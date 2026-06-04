import 'package:flutter_test/flutter_test.dart';
import 'package:screen_filter_app/models/advanced_config.dart';
import 'package:screen_filter_app/services/config_import_notifier.dart';

void main() {
  test(
    'uses aggregate import callback without duplicate section callbacks',
    () {
      final config = AppConfig(
        automationEnabled: true,
        focusMode: FocusModeConfig(enabled: true),
        spotlight: SpotlightConfig(enabled: true),
        regionMask: RegionMaskConfig(enabled: true),
        automationRules: [
          AutomationRule(processName: 'code.exe', presetName: '护眼'),
        ],
      );
      var aggregateCalls = 0;
      var sectionCalls = 0;

      notifyImportedConfig(
        config: config,
        onConfigImported: (_) => aggregateCalls++,
        onFocusModeChanged: (_) => sectionCalls++,
        onSpotlightChanged: (_) => sectionCalls++,
        onRegionMaskChanged: (_) => sectionCalls++,
        onAutomationRulesChanged: (_) => sectionCalls++,
        onAutomationEnabledChanged: (_) => sectionCalls++,
      );

      expect(aggregateCalls, 1);
      expect(sectionCalls, 0);
    },
  );

  test(
    'falls back to section callbacks when no aggregate callback is provided',
    () {
      final config = AppConfig(
        automationEnabled: true,
        focusMode: FocusModeConfig(enabled: true),
        spotlight: SpotlightConfig(enabled: true),
        regionMask: RegionMaskConfig(enabled: true),
        automationRules: [
          AutomationRule(processName: 'code.exe', presetName: '护眼'),
        ],
      );
      var focusCalls = 0;
      var spotlightCalls = 0;
      var regionCalls = 0;
      var rulesCalls = 0;
      var automationCalls = 0;

      notifyImportedConfig(
        config: config,
        onConfigImported: null,
        onFocusModeChanged: (_) => focusCalls++,
        onSpotlightChanged: (_) => spotlightCalls++,
        onRegionMaskChanged: (_) => regionCalls++,
        onAutomationRulesChanged: (_) => rulesCalls++,
        onAutomationEnabledChanged: (_) => automationCalls++,
      );

      expect(focusCalls, 1);
      expect(spotlightCalls, 1);
      expect(regionCalls, 1);
      expect(rulesCalls, 1);
      expect(automationCalls, 1);
    },
  );
}
