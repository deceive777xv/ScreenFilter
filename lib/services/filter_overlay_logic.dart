bool shouldPaintBaseShader({
  required bool shaderLoaded,
  required bool sandboxActive,
  required bool baseFilterEnabled,
  bool forceClear = false,
}) {
  return shaderLoaded && !sandboxActive && baseFilterEnabled && !forceClear;
}

bool shouldClearBaseShaderSurface({
  required bool shaderLoaded,
  required bool sandboxActive,
  required bool baseFilterEnabled,
  bool forceClear = false,
}) {
  return forceClear || (shaderLoaded && !sandboxActive && !baseFilterEnabled);
}

bool shouldOpenPanelForNativeRestoreOnStartup({
  required bool hasLastNativeFilterState,
}) {
  return hasLastNativeFilterState;
}

class BaseShaderPaintState {
  const BaseShaderPaintState({
    required this.width,
    required this.height,
    required this.brightness,
    required this.alpha,
    required this.baseColorValue,
  });

  final double width;
  final double height;
  final double brightness;
  final double alpha;
  final int baseColorValue;

  bool shouldRepaint(BaseShaderPaintState old) => this != old;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BaseShaderPaintState &&
          other.width == width &&
          other.height == height &&
          other.brightness == brightness &&
          other.alpha == alpha &&
          other.baseColorValue == baseColorValue;

  @override
  int get hashCode =>
      Object.hash(width, height, brightness, alpha, baseColorValue);
}
