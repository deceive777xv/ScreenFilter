import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import '../models/screen_post_process_effect.dart';

// ── Native function typedefs ────────────────────────────────────────────────

typedef _EngineInitC = Int32 Function();
typedef _EngineInitDart = int Function();

typedef _EngineCompileShaderC =
    Int32 Function(
      Pointer<Utf8> hlslCode,
      Int32 codeLength,
      Pointer<Utf8> errorBuf,
      Int32 errorBufSize,
    );
typedef _EngineCompileShaderDart =
    int Function(
      Pointer<Utf8> hlslCode,
      int codeLength,
      Pointer<Utf8> errorBuf,
      int errorBufSize,
    );

typedef _EngineSetUniformsC =
    Void Function(
      Float time,
      Float resX,
      Float resY,
      Float mouseX,
      Float mouseY,
      Float accentR,
      Float accentG,
      Float accentB,
      Float accentA,
    );
typedef _EngineSetUniformsDart =
    void Function(
      double time,
      double resX,
      double resY,
      double mouseX,
      double mouseY,
      double accentR,
      double accentG,
      double accentB,
      double accentA,
    );

typedef _EngineRenderFrameC = Int32 Function(Int32 width, Int32 height);
typedef _EngineRenderFrameDart = int Function(int width, int height);

typedef _EngineGetFramePixelsC =
    Int32 Function(Pointer<Uint8> outPixels, Int32 bufferSize);
typedef _EngineGetFramePixelsDart =
    int Function(Pointer<Uint8> outPixels, int bufferSize);

typedef _EngineShowOverlayC = Int32 Function(Int32 width, Int32 height);
typedef _EngineShowOverlayDart = int Function(int width, int height);

typedef _EngineRenderOverlayFrameC = Int32 Function(Int32 width, Int32 height);
typedef _EngineRenderOverlayFrameDart = int Function(int width, int height);

typedef _EngineSetFilterVisualsC =
    Void Function(Float opacity, Float brightness);
typedef _EngineSetFilterVisualsDart =
    void Function(double opacity, double brightness);

typedef _EngineSetPostProcessEffectC =
    Void Function(Int32 effect, Float intensity);
typedef _EngineSetPostProcessEffectDart =
    void Function(int effect, double intensity);

typedef _EngineHideOverlayC = Void Function();
typedef _EngineHideOverlayDart = void Function();

typedef _EngineIsOverlayActiveC = Int32 Function();
typedef _EngineIsOverlayActiveDart = int Function();

typedef _EngineSetRegionMaskC =
    Int32 Function(
      Int32 enabled,
      Int32 inverted,
      Int32 width,
      Int32 height,
      Pointer<Float> points,
      Pointer<Int32> regionPointCounts,
      Int32 regionCount,
    );
typedef _EngineSetRegionMaskDart =
    int Function(
      int enabled,
      int inverted,
      int width,
      int height,
      Pointer<Float> points,
      Pointer<Int32> regionPointCounts,
      int regionCount,
    );

typedef _EngineShutdownC = Void Function();
typedef _EngineShutdownDart = void Function();

/// Result of a shader compilation attempt.
class ShaderCompileResult {
  final bool success;
  final String errorMessage;

  const ShaderCompileResult({required this.success, this.errorMessage = ''});
}

/// FFI bridge to the native dx11_shader_engine.dll.
///
/// Provides runtime HLSL shader compilation and DX11 rendering.
class DX11ShaderEngine {
  late final DynamicLibrary _lib;
  bool _initialized = false;
  Pointer<Uint8>? _pixelBuf;
  int _pixelBufSize = 0;

  late final _EngineInitDart _init;
  late final _EngineCompileShaderDart _compileShader;
  late final _EngineSetUniformsDart _setUniforms;
  late final _EngineRenderFrameDart _renderFrame;
  late final _EngineGetFramePixelsDart _getFramePixels;
  late final _EngineShowOverlayDart _showOverlay;
  late final _EngineRenderOverlayFrameDart _renderOverlayFrame;
  late final _EngineSetFilterVisualsDart _setFilterVisuals;
  late final _EngineSetPostProcessEffectDart _setPostProcessEffect;
  late final _EngineHideOverlayDart _hideOverlay;
  late final _EngineIsOverlayActiveDart _isOverlayActive;
  late final _EngineSetRegionMaskDart _setRegionMask;
  late final _EngineShutdownDart _shutdown;

  bool get isInitialized => _initialized;

  /// Load the DLL and resolve all function symbols.
  bool load() {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      _lib = DynamicLibrary.open('$exeDir/dx11_shader_engine.dll');

      _init = _lib.lookupFunction<_EngineInitC, _EngineInitDart>('engine_init');
      _compileShader = _lib
          .lookupFunction<_EngineCompileShaderC, _EngineCompileShaderDart>(
            'engine_compile_shader',
          );
      _setUniforms = _lib
          .lookupFunction<_EngineSetUniformsC, _EngineSetUniformsDart>(
            'engine_set_uniforms',
          );
      _renderFrame = _lib
          .lookupFunction<_EngineRenderFrameC, _EngineRenderFrameDart>(
            'engine_render_frame',
          );
      _getFramePixels = _lib
          .lookupFunction<_EngineGetFramePixelsC, _EngineGetFramePixelsDart>(
            'engine_get_frame_pixels',
          );
      _showOverlay = _lib
          .lookupFunction<_EngineShowOverlayC, _EngineShowOverlayDart>(
            'engine_show_overlay',
          );
      _renderOverlayFrame = _lib
          .lookupFunction<
            _EngineRenderOverlayFrameC,
            _EngineRenderOverlayFrameDart
          >('engine_render_overlay_frame');
      _setFilterVisuals = _lib
          .lookupFunction<
            _EngineSetFilterVisualsC,
            _EngineSetFilterVisualsDart
          >('engine_set_filter_visuals');
      _setPostProcessEffect = _lib
          .lookupFunction<
            _EngineSetPostProcessEffectC,
            _EngineSetPostProcessEffectDart
          >('engine_set_post_process_effect');
      _hideOverlay = _lib
          .lookupFunction<_EngineHideOverlayC, _EngineHideOverlayDart>(
            'engine_hide_overlay',
          );
      _isOverlayActive = _lib
          .lookupFunction<_EngineIsOverlayActiveC, _EngineIsOverlayActiveDart>(
            'engine_is_overlay_active',
          );
      _setRegionMask = _lib
          .lookupFunction<_EngineSetRegionMaskC, _EngineSetRegionMaskDart>(
            'engine_set_region_mask',
          );
      _shutdown = _lib.lookupFunction<_EngineShutdownC, _EngineShutdownDart>(
        'engine_shutdown',
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Initialize the DirectX 11 device.
  bool initialize() {
    if (_initialized) return true;
    final result = _init();
    _initialized = (result == 0);
    return _initialized;
  }

  /// Compile an HLSL pixel shader and return compilation result.
  ShaderCompileResult compileShader(String hlslCode) {
    if (!_initialized) {
      return const ShaderCompileResult(
        success: false,
        errorMessage: 'Engine not initialized',
      );
    }

    final codePtr = hlslCode.toNativeUtf8();
    final codeUtf8Length = utf8.encode(hlslCode).length;
    const errorBufSize = 4096;
    final errorBuf = calloc<Uint8>(errorBufSize);

    try {
      final result = _compileShader(
        codePtr.cast(),
        codeUtf8Length,
        errorBuf.cast(),
        errorBufSize,
      );

      if (result == 0) {
        return const ShaderCompileResult(success: true);
      } else {
        final errorMsg = errorBuf.cast<Utf8>().toDartString();
        return ShaderCompileResult(success: false, errorMessage: errorMsg);
      }
    } finally {
      calloc.free(codePtr);
      calloc.free(errorBuf);
    }
  }

  /// Set uniform values for the next render.
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
    if (!_initialized) return;
    _setUniforms(
      time,
      resolutionX,
      resolutionY,
      mouseX,
      mouseY,
      accentR,
      accentG,
      accentB,
      accentA,
    );
  }

  /// Render a frame and return the RGBA pixel data.
  Uint8List? renderFrame(int width, int height) {
    if (!_initialized) return null;

    final result = _renderFrame(width, height);
    if (result != 0) return null;

    final bufferSize = width * height * 4;
    final pixelBuf = _ensurePixelBuffer(bufferSize);

    final readResult = _getFramePixels(pixelBuf, bufferSize);
    if (readResult != 0) return null;

    return Uint8List.fromList(pixelBuf.asTypedList(bufferSize));
  }

  bool showOverlay(int width, int height) {
    if (!_initialized) return false;
    return _showOverlay(width, height) == 0;
  }

  bool renderOverlayFrame(int width, int height) {
    if (!_initialized) return false;
    return _renderOverlayFrame(width, height) == 0;
  }

  void setFilterVisuals({required double opacity, required double brightness}) {
    if (!_initialized) return;
    _setFilterVisuals(opacity, brightness);
  }

  void setPostProcessEffect({
    required ScreenPostProcessEffect effect,
    required double intensity,
  }) {
    if (!_initialized) return;
    _setPostProcessEffect(effect.index, intensity);
  }

  void hideOverlay() {
    if (!_initialized) return;
    _hideOverlay();
  }

  bool get isOverlayActive {
    if (!_initialized) return false;
    return _isOverlayActive() != 0;
  }

  bool setRegionMask({
    required bool enabled,
    required bool inverted,
    required int width,
    required int height,
    required List<double> points,
    required List<int> regionPointCounts,
  }) {
    if (!_initialized) return false;
    final pointPtr = calloc<Float>(points.length);
    final countPtr = calloc<Int32>(regionPointCounts.length);
    try {
      for (var i = 0; i < points.length; i++) {
        pointPtr[i] = points[i];
      }
      for (var i = 0; i < regionPointCounts.length; i++) {
        countPtr[i] = regionPointCounts[i];
      }
      return _setRegionMask(
            enabled ? 1 : 0,
            inverted ? 1 : 0,
            width,
            height,
            pointPtr,
            countPtr,
            regionPointCounts.length,
          ) ==
          0;
    } finally {
      calloc.free(pointPtr);
      calloc.free(countPtr);
    }
  }

  /// Shutdown and release all DX11 resources.
  void dispose() {
    _freePixelBuffer();
    if (_initialized) {
      _hideOverlay();
      _shutdown();
      _initialized = false;
    }
  }

  Pointer<Uint8> _ensurePixelBuffer(int size) {
    final current = _pixelBuf;
    if (current != null && _pixelBufSize >= size) {
      return current;
    }

    _freePixelBuffer();
    _pixelBuf = calloc<Uint8>(size);
    _pixelBufSize = size;
    return _pixelBuf!;
  }

  void _freePixelBuffer() {
    final current = _pixelBuf;
    if (current == null) return;
    calloc.free(current);
    _pixelBuf = null;
    _pixelBufSize = 0;
  }
}
