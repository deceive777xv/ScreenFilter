import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/advanced_config.dart';
import 'dx11_shader_ffi.dart';
import 'win32_polling_service.dart';

/// Filter apply mode.
enum FilterApplyMode { none, static, dynamic }

typedef FilterImageDecoder =
    Future<ui.Image> Function(Uint8List pixels, int width, int height);

/// Manages the DX11 shader engine and fullscreen filter rendering.
///
/// Lives in [_FilterOverlayPageState] so it survives console panel
/// open/close cycles.  The sandbox page borrows this service for
/// preview rendering and shader compilation.
class ShaderFilterService {
  ShaderFilterService({
    DX11ShaderEngine? engine,
    FilterImageDecoder? decodePixels,
    Win32PollingService? win32PollingService,
    this.fallbackFrameInterval = const Duration(milliseconds: 66),
  }) : _engine = engine ?? DX11ShaderEngine(),
       _decodePixelsToImage = decodePixels ?? _defaultDecodePixels,
       _win32PollingService = win32PollingService ?? Win32PollingService(),
       _ownsWin32PollingService = win32PollingService == null;

  final DX11ShaderEngine _engine;
  final FilterImageDecoder _decodePixelsToImage;
  final Win32PollingService _win32PollingService;
  final bool _ownsWin32PollingService;
  final Duration fallbackFrameInterval;
  bool _engineReady = false;
  bool _shaderCompiled = false;
  bool _nativeOverlayActive = false;
  double? _lastFullscreenTime;
  double? _lastFullscreenMouseX;
  double? _lastFullscreenMouseY;
  Color? _lastFullscreenAccentColor;
  double? _lastFallbackFrameTime;
  RegionMaskConfig _regionMaskConfig = RegionMaskConfig();
  String? _lastRegionMaskSignature;

  /// Output image for the fullscreen filter overlay.
  final ValueNotifier<ui.Image?> filterImageNotifier = ValueNotifier(null);

  FilterApplyMode _mode = FilterApplyMode.none;
  Timer? _filterTimer;
  Win32PollingRelease? _cursorPollingRelease;
  final Stopwatch _stopwatch = Stopwatch();

  // Render state for filter
  Color _accentColor = const Color(0xFFFF8040);
  Size _screenSize = Size.zero;
  double _dpr = 1.0;
  double _filterOpacity = 1.0;
  double _filterBrightness = 0.0;

  // ── Getters ──────────────────────────────────────────────────
  bool get isEngineReady => _engineReady;
  bool get isShaderCompiled => _shaderCompiled;
  FilterApplyMode get mode => _mode;
  Size get screenSize => _screenSize;
  Size get filterRenderSize {
    if (_screenSize == Size.zero) return Size.zero;
    return Size(
      _toPhysicalPixels(_screenSize.width).toDouble(),
      _toPhysicalPixels(_screenSize.height).toDouble(),
    );
  }

  Color get accentColor => _accentColor;
  double get filterOpacity => _filterOpacity;
  double get filterBrightness => _filterBrightness;
  bool get isNativeOverlayActive =>
      _nativeOverlayActive && _engine.isOverlayActive;

  /// Notifies listeners when filter mode changes (for mutual exclusion).
  final ValueNotifier<FilterApplyMode> modeNotifier = ValueNotifier(
    FilterApplyMode.none,
  );

  // ── Lifecycle ────────────────────────────────────────────────

  void init() {
    if (_engineReady) return;
    if (_engine.load()) {
      _engineReady = _engine.initialize();
      if (_engineReady) {
        _engine.setFilterVisuals(
          opacity: _filterOpacity,
          brightness: _filterBrightness,
        );
        _syncRegionMaskToEngine();
      }
    }
  }

  void dispose() {
    _filterTimer?.cancel();
    _stopCursorPolling();
    _stopwatch.stop();
    _replaceFilterImage(null);
    _engine.hideOverlay();
    _engine.dispose();
    filterImageNotifier.dispose();
    if (_ownsWin32PollingService) {
      _win32PollingService.dispose();
    }
  }

  // ── Compilation ──────────────────────────────────────────────

  ShaderCompileResult compileShader(String code) {
    if (!_engineReady) {
      return const ShaderCompileResult(
        success: false,
        errorMessage: 'Engine not initialized',
      );
    }
    final result = _engine.compileShader(code);
    _shaderCompiled = result.success;
    return result;
  }

  // ── Preview rendering (called by sandbox page) ───────────────

  /// Render a frame at the given resolution.  Returns RGBA pixel
  /// data or null on failure.
  Uint8List? renderFrame({
    required int width,
    required int height,
    required double time,
    required double mouseX,
    required double mouseY,
    required Color accentColor,
  }) {
    if (!_engineReady || !_shaderCompiled) return null;
    _setUniforms(
      time: time,
      width: width,
      height: height,
      mouseX: mouseX,
      mouseY: mouseY,
      accentColor: accentColor,
    );
    return _engine.renderFrame(width, height);
  }

  // ── Fullscreen filter ────────────────────────────────────────

  void updateScreenSize(Size s) {
    if (_screenSize == s) return;
    _screenSize = s;
    _syncRegionMaskToEngine();
  }

  void updateAccentColor(Color c) => _accentColor = c;

  void updateDevicePixelRatio(double dpr) {
    final nextDpr = dpr > 0 ? dpr : 1.0;
    if (_dpr == nextDpr) return;
    _dpr = nextDpr;
    _syncRegionMaskToEngine();
  }

  void updateRegionMask(RegionMaskConfig config) {
    _regionMaskConfig = config;
    _syncRegionMaskToEngine();
  }

  void updateFilterVisuals({
    required double opacity,
    required double brightness,
  }) {
    final nextOpacity = opacity.clamp(0.0, 1.0);
    final nextBrightness = brightness.clamp(-1.0, 1.0);
    if (nextOpacity == _filterOpacity && nextBrightness == _filterBrightness) {
      return;
    }
    _filterOpacity = nextOpacity;
    _filterBrightness = nextBrightness;
    if (_engineReady) {
      _engine.setFilterVisuals(
        opacity: _filterOpacity,
        brightness: _filterBrightness,
      );
      _syncRegionMaskToEngine();
      _redrawNativeOverlayWithLastFrame();
    }
  }

  /// Read global mouse position, normalized to 0..1 based on screen size.
  Offset getGlobalMouseNormalized() {
    final cursorPosition = _win32PollingService.refreshCursorPosition();
    return _normalizeGlobalMouse(cursorPosition);
  }

  Offset get cachedGlobalMouseNormalized {
    return _normalizeGlobalMouse(_win32PollingService.cursorPosition.value);
  }

  /// Apply the current compiled shader as fullscreen filter.
  void applyFilter(
    FilterApplyMode newMode,
    Size screenSize,
    Color accentColor,
  ) {
    _mode = newMode;
    _lastFallbackFrameTime = null;
    _screenSize = screenSize;
    _accentColor = accentColor;
    modeNotifier.value = newMode;
    _filterTimer?.cancel();
    _filterTimer = null;

    if (newMode == FilterApplyMode.none) {
      _stopCursorPolling();
      _replaceFilterImage(null);
      _nativeOverlayActive = false;
      _engine.hideOverlay();
      return;
    }

    if (newMode == FilterApplyMode.dynamic) {
      _startCursorPolling();
    } else {
      _stopCursorPolling();
      _win32PollingService.refreshCursorPosition();
    }

    _nativeOverlayActive = _tryStartNativeOverlay();
    if (_nativeOverlayActive) {
      _replaceFilterImage(null);
    }

    if (newMode == FilterApplyMode.static) {
      // Render one frame and freeze.
      if (!_stopwatch.isRunning) _stopwatch.start();
      _renderFilterFrame();
      return;
    }

    // Dynamic — continuous rendering.
    if (!_stopwatch.isRunning) _stopwatch.start();
    _renderFilterFrame(); // render first frame immediately
    _startFilterTimer();
  }

  /// Stop the filter.
  void stopFilter() {
    _mode = FilterApplyMode.none;
    _lastFallbackFrameTime = null;
    _filterTimer?.cancel();
    _filterTimer = null;
    _stopCursorPolling();
    _replaceFilterImage(null);
    _nativeOverlayActive = false;
    _engine.hideOverlay();
    modeNotifier.value = FilterApplyMode.none;
  }

  void updateFallbackImage(ui.Image? image) {
    _replaceFilterImage(image);
  }

  // Called when the sandbox page takes over rendering (it will
  // push filter frames itself).
  void pauseOwnTimer() {
    _filterTimer?.cancel();
    _filterTimer = null;
  }

  // Called when the sandbox page disposes — if dynamic mode is
  // active the service resumes its own timer.
  void resumeOwnTimerIfNeeded() {
    if (_mode == FilterApplyMode.dynamic) {
      _startFilterTimer();
    }
  }

  // ── Internal ─────────────────────────────────────────────────

  void _startFilterTimer() {
    _filterTimer?.cancel();
    _filterTimer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      _renderFilterFrame();
    });
  }

  void _renderFilterFrame() {
    if (!_engineReady || !_shaderCompiled) return;
    if (_screenSize == Size.zero) return;

    final time = _stopwatch.elapsedMilliseconds / 1000.0;
    final mouse = cachedGlobalMouseNormalized;

    renderFullscreenFilterFrame(
      time: time,
      mouseX: mouse.dx,
      mouseY: mouse.dy,
      accentColor: _accentColor,
    );
  }

  void renderFullscreenFilterFrame({
    required double time,
    required double mouseX,
    required double mouseY,
    required Color accentColor,
  }) {
    if (!_engineReady || !_shaderCompiled) return;
    if (_screenSize == Size.zero) return;

    final renderSize = filterRenderSize;
    final w = renderSize.width.toInt();
    final h = renderSize.height.toInt();
    _lastFullscreenTime = time;
    _lastFullscreenMouseX = mouseX;
    _lastFullscreenMouseY = mouseY;
    _lastFullscreenAccentColor = accentColor;

    if (!_nativeOverlayActive && _shouldSkipFallbackFrame(time)) return;

    _setUniforms(
      time: time,
      width: w,
      height: h,
      mouseX: mouseX,
      mouseY: mouseY,
      accentColor: accentColor,
    );

    if (_nativeOverlayActive) {
      if (_engine.renderOverlayFrame(w, h)) {
        _replaceFilterImage(null);
        return;
      }
      _nativeOverlayActive = false;
      _engine.hideOverlay();
    }

    _lastFallbackFrameTime = time;
    final pixels = _engine.renderFrame(w, h);
    if (pixels != null) {
      _decodePixels(pixels, w, h);
    }
  }

  bool _shouldSkipFallbackFrame(double time) {
    if (_mode != FilterApplyMode.dynamic) return false;
    final lastTime = _lastFallbackFrameTime;
    if (lastTime == null) return false;
    final elapsedSeconds = time - lastTime;
    if (elapsedSeconds < 0) return false;
    final elapsed = Duration(
      microseconds: (elapsedSeconds * Duration.microsecondsPerSecond).round(),
    );
    return elapsed < fallbackFrameInterval;
  }

  bool _tryStartNativeOverlay() {
    if (!_engineReady || !_shaderCompiled) return false;
    final renderSize = filterRenderSize;
    if (renderSize == Size.zero) return false;
    _engine.setFilterVisuals(
      opacity: _filterOpacity,
      brightness: _filterBrightness,
    );
    _syncRegionMaskToEngine();
    return _engine.showOverlay(
      renderSize.width.toInt(),
      renderSize.height.toInt(),
    );
  }

  void _syncRegionMaskToEngine() {
    if (!_engineReady) return;
    final renderSize = filterRenderSize;
    if (renderSize == Size.zero) return;

    final enabled = _regionMaskConfig.enabled;
    final inverted = enabled && _regionMaskConfig.inverted;
    final activeRegions = enabled
        ? _regionMaskConfig.regions
              .where((region) => region.enabled && region.points.length >= 3)
              .toList()
        : const <MaskRegion>[];
    final points = <double>[];
    final regionPointCounts = <int>[];

    for (final region in activeRegions) {
      regionPointCounts.add(region.points.length);
      for (final point in region.points) {
        points.add(point.dx * _dpr);
        points.add(point.dy * _dpr);
      }
    }

    final signature = _regionMaskSignature(
      enabled: enabled,
      inverted: inverted,
      width: renderSize.width.toInt(),
      height: renderSize.height.toInt(),
      points: points,
      regionPointCounts: regionPointCounts,
    );
    if (signature == _lastRegionMaskSignature) return;

    if (_engine.setRegionMask(
      enabled: enabled,
      inverted: inverted,
      width: renderSize.width.toInt(),
      height: renderSize.height.toInt(),
      points: points,
      regionPointCounts: regionPointCounts,
    )) {
      _lastRegionMaskSignature = signature;
      _redrawNativeOverlayWithLastFrame();
    }
  }

  String _regionMaskSignature({
    required bool enabled,
    required bool inverted,
    required int width,
    required int height,
    required List<double> points,
    required List<int> regionPointCounts,
  }) {
    final pointText = points.map((point) => point.toStringAsFixed(2)).join(',');
    final countText = regionPointCounts.join(',');
    return '$enabled|$inverted|$width|$height|$countText|$pointText';
  }

  void _redrawNativeOverlayWithLastFrame() {
    if (!_nativeOverlayActive) return;
    final time = _lastFullscreenTime;
    final mouseX = _lastFullscreenMouseX;
    final mouseY = _lastFullscreenMouseY;
    final accentColor = _lastFullscreenAccentColor;
    if (time == null ||
        mouseX == null ||
        mouseY == null ||
        accentColor == null) {
      return;
    }

    final renderSize = filterRenderSize;
    if (renderSize == Size.zero) return;
    final w = renderSize.width.toInt();
    final h = renderSize.height.toInt();

    _setUniforms(
      time: time,
      width: w,
      height: h,
      mouseX: mouseX,
      mouseY: mouseY,
      accentColor: accentColor,
    );

    if (!_engine.renderOverlayFrame(w, h)) {
      _nativeOverlayActive = false;
      _engine.hideOverlay();
    }
  }

  void _setUniforms({
    required double time,
    required int width,
    required int height,
    required double mouseX,
    required double mouseY,
    required Color accentColor,
  }) {
    _engine.setUniforms(
      time: time,
      resolutionX: width.toDouble(),
      resolutionY: height.toDouble(),
      mouseX: mouseX,
      mouseY: mouseY,
      accentR: accentColor.r,
      accentG: accentColor.g,
      accentB: accentColor.b,
      accentA: accentColor.a,
    );
  }

  int _toPhysicalPixels(double logicalPixels) {
    final pixels = (logicalPixels * _dpr).round();
    return pixels < 1 ? 1 : pixels;
  }

  Offset _normalizeGlobalMouse(Offset cursorPosition) {
    if (_screenSize == Size.zero) return const Offset(0.5, 0.5);
    final renderSize = filterRenderSize;
    return Offset(
      (cursorPosition.dx / renderSize.width).clamp(0.0, 1.0),
      (cursorPosition.dy / renderSize.height).clamp(0.0, 1.0),
    );
  }

  void _startCursorPolling() {
    _cursorPollingRelease ??= _win32PollingService.retainCursorPolling();
  }

  void _stopCursorPolling() {
    _cursorPollingRelease?.call();
    _cursorPollingRelease = null;
  }

  Future<void> _decodePixels(Uint8List pixels, int w, int h) async {
    final image = await _decodePixelsToImage(pixels, w, h);
    // Guard against stale async decode completing after stopFilter().
    if (_mode != FilterApplyMode.none && !_nativeOverlayActive) {
      _replaceFilterImage(image);
    } else {
      image.dispose();
    }
  }

  void _replaceFilterImage(ui.Image? nextImage) {
    final previousImage = filterImageNotifier.value;
    if (identical(previousImage, nextImage)) return;
    filterImageNotifier.value = nextImage;
    previousImage?.dispose();
  }

  static Future<ui.Image> _defaultDecodePixels(
    Uint8List pixels,
    int w,
    int h,
  ) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      w,
      h,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }
}
