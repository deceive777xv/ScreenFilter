import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'dx11_shader_ffi.dart';

// Win32 GetCursorPos via FFI for global mouse position.
final _user32 = DynamicLibrary.open('user32.dll');

final class _POINT extends Struct {
  @Int32()
  external int x;
  @Int32()
  external int y;
}

typedef _GetCursorPosC = Int32 Function(Pointer<_POINT>);
typedef _GetCursorPosDart = int Function(Pointer<_POINT>);
final _getCursorPos =
    _user32.lookupFunction<_GetCursorPosC, _GetCursorPosDart>('GetCursorPos');

/// Filter apply mode.
enum FilterApplyMode { none, static, dynamic }

/// Manages the DX11 shader engine and fullscreen filter rendering.
///
/// Lives in [_FilterOverlayPageState] so it survives console panel
/// open/close cycles.  The sandbox page borrows this service for
/// preview rendering and shader compilation.
class ShaderFilterService {
  final DX11ShaderEngine _engine = DX11ShaderEngine();
  bool _engineReady = false;
  bool _shaderCompiled = false;

  /// Output image for the fullscreen filter overlay.
  final ValueNotifier<ui.Image?> filterImageNotifier = ValueNotifier(null);

  FilterApplyMode _mode = FilterApplyMode.none;
  Timer? _filterTimer;
  final Stopwatch _stopwatch = Stopwatch();

  // Render state for filter
  Color _accentColor = const Color(0xFFFF8040);
  Size _screenSize = Size.zero;
  double _dpr = 1.0;

  // ── Getters ──────────────────────────────────────────────────
  bool get isEngineReady => _engineReady;
  bool get isShaderCompiled => _shaderCompiled;
  FilterApplyMode get mode => _mode;
  Size get screenSize => _screenSize;
  Color get accentColor => _accentColor;

  /// Notifies listeners when filter mode changes (for mutual exclusion).
  final ValueNotifier<FilterApplyMode> modeNotifier = ValueNotifier(FilterApplyMode.none);

  // ── Lifecycle ────────────────────────────────────────────────

  void init() {
    if (_engineReady) return;
    if (_engine.load()) {
      _engineReady = _engine.initialize();
    }
  }

  void dispose() {
    _filterTimer?.cancel();
    _stopwatch.stop();
    _engine.dispose();
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
    return _engine.renderFrame(width, height);
  }

  // ── Fullscreen filter ────────────────────────────────────────

  void updateScreenSize(Size s) => _screenSize = s;
  void updateAccentColor(Color c) => _accentColor = c;
  void updateDevicePixelRatio(double dpr) => _dpr = dpr;

  /// Read global mouse position, normalized to 0..1 based on screen size.
  Offset getGlobalMouseNormalized() {
    final pt = calloc<_POINT>();
    try {
      _getCursorPos(pt);
      if (_screenSize == Size.zero) return const Offset(0.5, 0.5);
      // GetCursorPos returns physical screen coordinates; normalize using
      // physical size (logical × devicePixelRatio) so DPI-scaled displays work.
      final physW = _screenSize.width * _dpr;
      final physH = _screenSize.height * _dpr;
      return Offset(
        (pt.ref.x / physW).clamp(0.0, 1.0),
        (pt.ref.y / physH).clamp(0.0, 1.0),
      );
    } finally {
      calloc.free(pt);
    }
  }

  /// Apply the current compiled shader as fullscreen filter.
  void applyFilter(FilterApplyMode newMode, Size screenSize, Color accentColor) {
    _mode = newMode;
    _screenSize = screenSize;
    _accentColor = accentColor;    modeNotifier.value = newMode;
    _filterTimer?.cancel();
    _filterTimer = null;

    if (newMode == FilterApplyMode.none) {
      filterImageNotifier.value = null;
      return;
    }

    if (newMode == FilterApplyMode.static) {
      // Render one frame and freeze.
      if (!_stopwatch.isRunning) _stopwatch.start();
      _renderFilterFrame();
      return;
    }

    // Dynamic — continuous rendering.
    if (!_stopwatch.isRunning) _stopwatch.start();
    _startFilterTimer();
  }

  /// Stop the filter.
  void stopFilter() {
    _mode = FilterApplyMode.none;
    _filterTimer?.cancel();
    _filterTimer = null;
    filterImageNotifier.value = null;
    modeNotifier.value = FilterApplyMode.none;
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
    final w = _screenSize.width.toInt();
    final h = _screenSize.height.toInt();
    final mouse = getGlobalMouseNormalized();

    _engine.setUniforms(
      time: time,
      resolutionX: _screenSize.width,
      resolutionY: _screenSize.height,
      mouseX: mouse.dx,
      mouseY: mouse.dy,
      accentR: _accentColor.r,
      accentG: _accentColor.g,
      accentB: _accentColor.b,
      accentA: _accentColor.a,
    );

    final pixels = _engine.renderFrame(w, h);
    if (pixels != null) {
      _decodePixels(pixels, w, h);
    }
  }

  Future<void> _decodePixels(Uint8List pixels, int w, int h) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels, w, h, ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final image = await completer.future;
    // Guard against stale async decode completing after stopFilter().
    if (_mode != FilterApplyMode.none) {
      filterImageNotifier.value = image;
    }
  }
}
