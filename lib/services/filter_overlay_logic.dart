bool shouldPaintBaseShader({
  required bool shaderLoaded,
  required bool sandboxActive,
  required bool baseFilterEnabled,
  bool forceClear = false,
  bool suppressForNativeRestore = false,
}) {
  return shaderLoaded &&
      !sandboxActive &&
      baseFilterEnabled &&
      !forceClear; // !suppressForNativeRestore;抑制会导致无法正常渲染控制台
}

bool shouldClearBaseShaderSurface({
  required bool shaderLoaded,
  required bool sandboxActive,
  required bool baseFilterEnabled,
  bool forceClear = false,
  bool suppressForNativeRestore = false,
}) {
  return forceClear ||
      suppressForNativeRestore ||
      (shaderLoaded && !sandboxActive && !baseFilterEnabled);
}

bool shouldOpenPanelForNativeRestoreOnStartup({
  required bool hasLastNativeFilterState,
}) {
  return false;
}

bool shouldPrimeNativeRestoreOnStartup({
  required bool hasLastNativeFilterState,
}) {
  return hasLastNativeFilterState;
}

bool shouldRenderPanel({
  required bool panelOpen,
  required bool nativeRestoreStartupPending,
  required bool startupSurfaceReady,
}) {
  return panelOpen;
}

bool shouldOpenPanelAfterNativeRestoreAttempt({
  required bool nativeRestorePendingOnStartup,
  required bool nativeRestoreSucceeded,
}) {
  return nativeRestorePendingOnStartup && !nativeRestoreSucceeded;
}

bool shouldRenderTopLayerComponents({
  required bool nativeOverlayActive,
  bool startupNativeRestoreInProgress = false,
}) {
  return !nativeOverlayActive && !startupNativeRestoreInProgress;
}

bool shouldShowOverlayComponentControlActiveState({
  required bool componentEnabled,
  required bool nativeOverlayActive,
}) {
  return componentEnabled && !nativeOverlayActive;
}

bool shouldAllowOverlayComponentControl({required bool nativeOverlayActive}) {
  return !nativeOverlayActive;
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
