import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_filter_app/models/advanced_config.dart';
import 'package:screen_filter_app/services/settings_service.dart';
import 'package:screen_filter_app/ui/advanced/advanced_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('dim opacity controls show two decimal places', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await SettingsService.init();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AdvancedPage(
            settingsService: settings,
            focusModeConfig: FocusModeConfig(enabled: true, dimOpacity: 0.55),
            spotlightConfig: SpotlightConfig(enabled: true, dimOpacity: 0.65),
            regionMaskConfig: RegionMaskConfig(),
            automationRules: const [],
            automationEnabled: false,
            consoleHotkeyConfig: const ConsoleHotkeyConfig(),
            onFocusModeChanged: (_) {},
            onSpotlightChanged: (_) {},
            onConsoleHotkeyChanged: (_) {},
            onRegionMaskChanged: (_) {},
            onStartDrawingRegion: () {},
            onAutomationRulesChanged: (_) {},
            onAutomationEnabledChanged: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('0.55'), findsOneWidget);
    expect(find.text('0.65'), findsOneWidget);
  });
}
