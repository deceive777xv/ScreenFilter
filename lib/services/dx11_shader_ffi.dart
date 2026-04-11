import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

// ── Native function typedefs ────────────────────────────────────────────────

typedef _EngineInitC = Int32 Function();
typedef _EngineInitDart = int Function();

typedef _EngineCompileShaderC = Int32 Function(
    Pointer<Utf8> hlslCode, Int32 codeLength,
    Pointer<Utf8> errorBuf, Int32 errorBufSize);
typedef _EngineCompileShaderDart = int Function(
    Pointer<Utf8> hlslCode, int codeLength,
    Pointer<Utf8> errorBuf, int errorBufSize);

typedef _EngineSetUniformsC = Void Function(
    Float time, Float resX, Float resY,
    Float mouseX, Float mouseY,
    Float accentR, Float accentG, Float accentB, Float accentA);
typedef _EngineSetUniformsDart = void Function(
    double time, double resX, double resY,
    double mouseX, double mouseY,
    double accentR, double accentG, double accentB, double accentA);

typedef _EngineRenderFrameC = Int32 Function(Int32 width, Int32 height);
typedef _EngineRenderFrameDart = int Function(int width, int height);

typedef _EngineGetFramePixelsC = Int32 Function(
    Pointer<Uint8> outPixels, Int32 bufferSize);
typedef _EngineGetFramePixelsDart = int Function(
    Pointer<Uint8> outPixels, int bufferSize);

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

  late final _EngineInitDart _init;
  late final _EngineCompileShaderDart _compileShader;
  late final _EngineSetUniformsDart _setUniforms;
  late final _EngineRenderFrameDart _renderFrame;
  late final _EngineGetFramePixelsDart _getFramePixels;
  late final _EngineShutdownDart _shutdown;

  bool get isInitialized => _initialized;

  /// Load the DLL and resolve all function symbols.
  bool load() {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      _lib = DynamicLibrary.open('$exeDir/dx11_shader_engine.dll');

      _init = _lib.lookupFunction<_EngineInitC, _EngineInitDart>('engine_init');
      _compileShader = _lib.lookupFunction<_EngineCompileShaderC, _EngineCompileShaderDart>('engine_compile_shader');
      _setUniforms = _lib.lookupFunction<_EngineSetUniformsC, _EngineSetUniformsDart>('engine_set_uniforms');
      _renderFrame = _lib.lookupFunction<_EngineRenderFrameC, _EngineRenderFrameDart>('engine_render_frame');
      _getFramePixels = _lib.lookupFunction<_EngineGetFramePixelsC, _EngineGetFramePixelsDart>('engine_get_frame_pixels');
      _shutdown = _lib.lookupFunction<_EngineShutdownC, _EngineShutdownDart>('engine_shutdown');

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
          success: false, errorMessage: 'Engine not initialized');
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
    _setUniforms(time, resolutionX, resolutionY, mouseX, mouseY,
        accentR, accentG, accentB, accentA);
  }

  /// Render a frame and return the RGBA pixel data.
  Uint8List? renderFrame(int width, int height) {
    if (!_initialized) return null;

    final result = _renderFrame(width, height);
    if (result != 0) return null;

    final bufferSize = width * height * 4;
    final pixelBuf = calloc<Uint8>(bufferSize);

    try {
      final readResult = _getFramePixels(pixelBuf, bufferSize);
      if (readResult != 0) return null;

      return Uint8List.fromList(pixelBuf.asTypedList(bufferSize));
    } finally {
      calloc.free(pixelBuf);
    }
  }

  /// Shutdown and release all DX11 resources.
  void dispose() {
    if (_initialized) {
      _shutdown();
      _initialized = false;
    }
  }
}
