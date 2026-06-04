import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_filter_app/models/advanced_config.dart';
import 'package:screen_filter_app/services/dx11_shader_ffi.dart';
import 'package:screen_filter_app/services/shader_filter_service.dart';

void main() {
  test('uses physical pixels for fullscreen shader filter rendering', () {
    final service = ShaderFilterService();

    service.updateScreenSize(const Size(1536, 864));
    service.updateDevicePixelRatio(1.25);

    expect(service.filterRenderSize, const Size(1920, 1080));
  });

  test('stores clamped fullscreen filter visuals for all render backends', () {
    final service = ShaderFilterService();

    service.updateFilterVisuals(opacity: 1.4, brightness: -1.2);

    expect(service.filterOpacity, 1.0);
    expect(service.filterBrightness, -1.0);

    service.updateFilterVisuals(opacity: -0.2, brightness: 1.3);

    expect(service.filterOpacity, 0.0);
    expect(service.filterBrightness, 1.0);
  });

  test('redraws native overlay when fullscreen visuals change', () {
    final engine = _FakeDX11ShaderEngine();
    final service = ShaderFilterService(engine: engine);

    service.init();
    service.compileShader('float4 main() : SV_TARGET { return 1; }');
    service.updateScreenSize(const Size(100, 80));
    service.applyFilter(
      FilterApplyMode.static,
      const Size(100, 80),
      Colors.white,
    );

    expect(engine.renderOverlayFrameCalls, 1);

    service.updateFilterVisuals(opacity: 0.4, brightness: 0.2);

    expect(engine.lastOpacity, 0.4);
    expect(engine.lastBrightness, 0.2);
    expect(engine.renderOverlayFrameCalls, 2);
    expect(engine.renderFrameCalls, 0);
  });

  test('uploads enabled region mask polygons in physical pixels', () {
    final engine = _FakeDX11ShaderEngine();
    final service = ShaderFilterService(engine: engine);

    service.init();
    service.updateScreenSize(const Size(100, 80));
    service.updateDevicePixelRatio(2.0);
    service.updateRegionMask(
      RegionMaskConfig(
        enabled: true,
        regions: [
          MaskRegion(
            id: 'a',
            points: const [Offset(1, 2), Offset(3, 4), Offset(5, 6)],
          ),
          MaskRegion(
            id: 'disabled',
            enabled: false,
            points: const [Offset(10, 10), Offset(20, 10), Offset(10, 20)],
          ),
        ],
        inverted: true,
      ),
    );

    expect(engine.lastMaskEnabled, isTrue);
    expect(engine.lastMaskInverted, isTrue);
    expect(engine.lastMaskWidth, 200);
    expect(engine.lastMaskHeight, 160);
    expect(engine.lastMaskCounts, [3]);
    expect(engine.lastMaskPoints, [2.0, 4.0, 6.0, 8.0, 10.0, 12.0]);
  });

  test('throttles dynamic fullscreen fallback rendering', () {
    final engine = _FakeDX11ShaderEngine()
      ..overlayCanStart = false
      ..nextFramePixels = null;
    final service = ShaderFilterService(
      engine: engine,
      fallbackFrameInterval: const Duration(milliseconds: 66),
    );

    service.init();
    service.compileShader('float4 main() : SV_TARGET { return 1; }');
    service.updateScreenSize(const Size(1, 1));
    service.applyFilter(
      FilterApplyMode.dynamic,
      const Size(1, 1),
      Colors.white,
    );
    service.pauseOwnTimer();

    expect(engine.renderFrameCalls, 1);

    service.renderFullscreenFilterFrame(
      time: 0.03,
      mouseX: 0.5,
      mouseY: 0.5,
      accentColor: Colors.white,
    );

    expect(engine.renderFrameCalls, 1);

    service.renderFullscreenFilterFrame(
      time: 0.07,
      mouseX: 0.5,
      mouseY: 0.5,
      accentColor: Colors.white,
    );

    expect(engine.renderFrameCalls, 2);
    service.stopFilter();
  });

  test('skips fallback uniform updates while throttled', () {
    final engine = _FakeDX11ShaderEngine()
      ..overlayCanStart = false
      ..nextFramePixels = null;
    final service = ShaderFilterService(
      engine: engine,
      fallbackFrameInterval: const Duration(milliseconds: 66),
    );

    service.init();
    service.compileShader('float4 main() : SV_TARGET { return 1; }');
    service.updateScreenSize(const Size(1, 1));
    service.applyFilter(
      FilterApplyMode.dynamic,
      const Size(1, 1),
      Colors.white,
    );
    service.pauseOwnTimer();

    expect(engine.renderFrameCalls, 1);
    expect(engine.setUniformCalls, 1);

    service.renderFullscreenFilterFrame(
      time: 0.03,
      mouseX: 0.5,
      mouseY: 0.5,
      accentColor: Colors.white,
    );

    expect(engine.renderFrameCalls, 1);
    expect(engine.setUniformCalls, 1);
    service.stopFilter();
  });

  testWidgets('disposes replaced and stopped fallback images', (tester) async {
    final engine = _FakeDX11ShaderEngine()
      ..overlayCanStart = false
      ..nextFramePixels = _solidRgbaPixel(0xFF);
    final decodedImages = <ui.Image>[
      (await tester.runAsync<ui.Image>(() => createTestImage(cache: false)))!,
      (await tester.runAsync<ui.Image>(() => createTestImage(cache: false)))!,
    ];
    var decodeIndex = 0;
    final service = ShaderFilterService(
      engine: engine,
      decodePixels: (_, _, _) async => decodedImages[decodeIndex++],
    );

    service.init();
    service.compileShader('float4 main() : SV_TARGET { return 1; }');
    service.updateScreenSize(const Size(1, 1));
    service.applyFilter(FilterApplyMode.static, const Size(1, 1), Colors.white);

    expect(engine.renderFrameCalls, 1);
    final firstImage = await _waitForFilterImage(tester, service);
    expect(firstImage.debugDisposed, isFalse);

    engine.nextFramePixels = _solidRgbaPixel(0x80);
    service.renderFullscreenFilterFrame(
      time: 1,
      mouseX: 0.5,
      mouseY: 0.5,
      accentColor: Colors.white,
    );

    final secondImage = await _waitForFilterImage(
      tester,
      service,
      previous: firstImage,
    );
    expect(firstImage.debugDisposed, isTrue);
    expect(secondImage.debugDisposed, isFalse);

    service.stopFilter();
    expect(service.filterImageNotifier.value, isNull);
    expect(secondImage.debugDisposed, isTrue);
  });
}

Uint8List _solidRgbaPixel(int alpha) => Uint8List.fromList([255, 0, 0, alpha]);

Future<ui.Image> _waitForFilterImage(
  WidgetTester tester,
  ShaderFilterService service, {
  ui.Image? previous,
}) async {
  final image = await tester.runAsync<ui.Image?>(() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final image = service.filterImageNotifier.value;
      if (image != null && image != previous) {
        return image;
      }
    }
    return null;
  });
  if (image != null) {
    return image;
  }
  fail('Timed out waiting for filter image');
}

class _FakeDX11ShaderEngine implements DX11ShaderEngine {
  double? lastOpacity;
  double? lastBrightness;
  int renderOverlayFrameCalls = 0;
  int renderFrameCalls = 0;
  int setUniformCalls = 0;
  bool overlayActive = false;
  bool overlayCanStart = true;
  Uint8List? nextFramePixels;
  bool? lastMaskEnabled;
  bool? lastMaskInverted;
  int? lastMaskWidth;
  int? lastMaskHeight;
  List<int>? lastMaskCounts;
  List<double>? lastMaskPoints;

  @override
  bool get isInitialized => true;

  @override
  bool get isOverlayActive => overlayActive;

  @override
  ShaderCompileResult compileShader(String hlslCode) {
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
  Uint8List? renderFrame(int width, int height) {
    renderFrameCalls++;
    return nextFramePixels;
  }

  @override
  bool renderOverlayFrame(int width, int height) {
    renderOverlayFrameCalls++;
    return overlayActive;
  }

  @override
  bool setRegionMask({
    required bool enabled,
    required bool inverted,
    required int width,
    required int height,
    required List<double> points,
    required List<int> regionPointCounts,
  }) {
    lastMaskEnabled = enabled;
    lastMaskInverted = inverted;
    lastMaskWidth = width;
    lastMaskHeight = height;
    lastMaskPoints = List<double>.from(points);
    lastMaskCounts = List<int>.from(regionPointCounts);
    return true;
  }

  @override
  void setFilterVisuals({required double opacity, required double brightness}) {
    lastOpacity = opacity;
    lastBrightness = brightness;
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
  }) {
    setUniformCalls++;
  }

  @override
  bool showOverlay(int width, int height) {
    overlayActive = overlayCanStart;
    return overlayCanStart;
  }
}
