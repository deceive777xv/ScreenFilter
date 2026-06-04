import '../models/advanced_config.dart';

void notifyImportedConfig({
  required AppConfig config,
  required void Function(AppConfig config)? onConfigImported,
  required void Function(FocusModeConfig config) onFocusModeChanged,
  required void Function(SpotlightConfig config) onSpotlightChanged,
  required void Function(RegionMaskConfig config) onRegionMaskChanged,
  required void Function(List<AutomationRule> rules) onAutomationRulesChanged,
  required void Function(bool enabled) onAutomationEnabledChanged,
  required void Function(ConsoleHotkeyConfig config) onConsoleHotkeyChanged,
}) {
  final aggregateCallback = onConfigImported;
  if (aggregateCallback != null) {
    aggregateCallback(config);
    return;
  }

  onFocusModeChanged(config.focusMode);
  onSpotlightChanged(config.spotlight);
  onRegionMaskChanged(config.regionMask);
  onAutomationRulesChanged(config.automationRules);
  onAutomationEnabledChanged(config.automationEnabled);
  onConsoleHotkeyChanged(config.consoleHotkey);
}
