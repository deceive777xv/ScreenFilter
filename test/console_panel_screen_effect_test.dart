import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_filter_app/models/advanced_config.dart';
import 'package:screen_filter_app/models/overlay_component.dart';
import 'package:screen_filter_app/models/screen_post_process_effect.dart';
import 'package:screen_filter_app/services/dx11_shader_ffi.dart';
import 'package:screen_filter_app/services/settings_service.dart';
import 'package:screen_filter_app/services/shader_filter_service.dart';
import 'package:screen_filter_app/ui/console_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'opening the sandbox from the console preserves active screen effect state',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final settings = await SettingsService.init();
      final engine = _FakeDX11ShaderEngine();
      final service = ShaderFilterService(engine: engine);

      service.init();
      service.updateScreenSize(const Size(720, 560));
      service.applyFilter(
        FilterApplyMode.dynamic,
        const Size(720, 560),
        Colors.white,
        postProcessEffect: ScreenPostProcessEffect.mosaic,
        origin: FilterApplyOrigin.screenEffect,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ConsolePanel(
              brightness: 0,
              alpha: 1,
              baseColor: Colors.transparent,
              settingsService: settings,
              clockComponent: OverlayComponent.createClock(),
              sloganComponent: OverlayComponent.createSlogan(),
              watermarkComponent: OverlayComponent.createWatermark(),
              onOverlayChanged: (_) {},
              shaderFilterService: service,
              focusModeConfig: FocusModeConfig(),
              spotlightConfig: SpotlightConfig(),
              automationRules: const [],
              automationEnabled: false,
              consoleHotkeyConfig: const ConsoleHotkeyConfig(),
              onFocusModeChanged: (_) {},
              onSpotlightChanged: (_) {},
              onConsoleHotkeyChanged: (_) {},
              regionMaskConfig: RegionMaskConfig(),
              onRegionMaskChanged: (_) {},
              onStartDrawingRegion: () {},
              onAutomationRulesChanged: (_) {},
              onAutomationEnabledChanged: (_) {},
              onBrightnessChanged: (_) {},
              onAlphaChanged: (_) {},
              onBaseColorChanged: (_) {},
              onClose: () {},
              enableSystemProbes: false,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.code_outlined));

      expect(service.mode, FilterApplyMode.dynamic);
      expect(service.filterOrigin, FilterApplyOrigin.screenEffect);
      expect(service.postProcessEffect, ScreenPostProcessEffect.mosaic);
      expect(engine.lastPostProcessEffect, ScreenPostProcessEffect.mosaic);
      expect(engine.compileShaderCalls, 0);

      service.stopFilter();
    },
  );
}

class _FakeDX11ShaderEngine implements DX11ShaderEngine {
  bool overlayActive = false;
  int compileShaderCalls = 0;
  int compilePreviewShaderCalls = 0;
  ScreenPostProcessEffect? lastPostProcessEffect;
  double? lastPostProcessIntensity;

  @override
  bool get isInitialized => true;

  @override
  bool get isOverlayActive => overlayActive;

  @override
  ShaderCompileResult compileShader(String hlslCode) {
    compileShaderCalls++;
    return const ShaderCompileResult(success: true);
  }

  @override
  ShaderCompileResult compilePreviewShader(String hlslCode) {
    compilePreviewShaderCalls++;
    return const ShaderCompileResult(success: true);
  }

  @override
  void dispose() {}

  @override
  void hideOverlay() {
    overlayActive = false;
  }

  @override
  bool initialize() => true;

  @override
  bool load() => true;

  @override
  Uint8List? renderFrame(int width, int height) => null;

  @override
  Uint8List? renderPreviewFrame(int width, int height) => null;

  @override
  bool renderOverlayFrame(int width, int height) => overlayActive;

  @override
  bool setRegionMask({
    required bool enabled,
    required bool inverted,
    required int width,
    required int height,
    required List<double> points,
    required List<int> regionPointCounts,
  }) {
    return true;
  }

  @override
  void setFilterVisuals({
    required double opacity,
    required double brightness,
  }) {}

  @override
  void setPostProcessEffect({
    required ScreenPostProcessEffect effect,
    required double intensity,
  }) {
    lastPostProcessEffect = effect;
    lastPostProcessIntensity = intensity;
  }

  @override
  void setUniforms({
    required double time,
    required double resolutionX,
    required double resolutionY,
    double mouseX = 0,
    double mouseY = 0,
    double accentR = 1,
    double accentG = 1,
    double accentB = 1,
    double accentA = 1,
  }) {}

  @override
  bool showOverlay(int width, int height) {
    overlayActive = true;
    return true;
  }
}
