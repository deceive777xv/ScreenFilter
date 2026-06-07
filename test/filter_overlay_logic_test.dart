import 'package:flutter_test/flutter_test.dart';
import 'package:screen_filter_app/services/filter_overlay_logic.dart';

void main() {
  test('skips base shader when no visual filter is active', () {
    expect(
      shouldPaintBaseShader(
        shaderLoaded: true,
        sandboxActive: false,
        baseFilterEnabled: false,
      ),
      isFalse,
    );
  });

  test('clears the base shader surface when a loaded filter is turned off', () {
    expect(
      shouldClearBaseShaderSurface(
        shaderLoaded: true,
        sandboxActive: false,
        baseFilterEnabled: false,
      ),
      isTrue,
    );
    expect(
      shouldClearBaseShaderSurface(
        shaderLoaded: true,
        sandboxActive: true,
        baseFilterEnabled: false,
      ),
      isFalse,
    );
  });

  test('force clear takes precedence over painting an active base filter', () {
    expect(
      shouldPaintBaseShader(
        shaderLoaded: true,
        sandboxActive: false,
        baseFilterEnabled: true,
        forceClear: true,
      ),
      isFalse,
    );
    expect(
      shouldClearBaseShaderSurface(
        shaderLoaded: false,
        sandboxActive: true,
        baseFilterEnabled: true,
        forceClear: true,
      ),
      isTrue,
    );
  });

  test('native restore startup suppresses base shader painting', () {
    expect(
      shouldPaintBaseShader(
        shaderLoaded: true,
        sandboxActive: false,
        baseFilterEnabled: true,
        suppressForNativeRestore: true,
      ),
      isFalse,
    );
    expect(
      shouldClearBaseShaderSurface(
        shaderLoaded: true,
        sandboxActive: false,
        baseFilterEnabled: true,
        suppressForNativeRestore: true,
      ),
      isTrue,
    );
  });

  test('primes native restore on startup without opening the panel', () {
    expect(
      shouldPrimeNativeRestoreOnStartup(hasLastNativeFilterState: true),
      isTrue,
    );
    expect(
      shouldPrimeNativeRestoreOnStartup(hasLastNativeFilterState: false),
      isFalse,
    );
    expect(
      shouldOpenPanelForNativeRestoreOnStartup(hasLastNativeFilterState: true),
      isFalse,
    );
    expect(
      shouldOpenPanelForNativeRestoreOnStartup(hasLastNativeFilterState: false),
      isFalse,
    );
  });

  test('renders panel whenever the panel flag is open', () {
    expect(
      shouldRenderPanel(
        panelOpen: true,
        nativeRestoreStartupPending: true,
        startupSurfaceReady: false,
      ),
      isTrue,
    );
    expect(
      shouldRenderPanel(
        panelOpen: true,
        nativeRestoreStartupPending: true,
        startupSurfaceReady: true,
      ),
      isTrue,
    );
    expect(
      shouldRenderPanel(
        panelOpen: true,
        nativeRestoreStartupPending: false,
        startupSurfaceReady: false,
      ),
      isTrue,
    );
    expect(
      shouldRenderPanel(
        panelOpen: false,
        nativeRestoreStartupPending: true,
        startupSurfaceReady: true,
      ),
      isFalse,
    );
  });

  test('opens startup panel only when native restore fails', () {
    expect(
      shouldOpenPanelAfterNativeRestoreAttempt(
        nativeRestorePendingOnStartup: true,
        nativeRestoreSucceeded: false,
      ),
      isTrue,
    );
    expect(
      shouldOpenPanelAfterNativeRestoreAttempt(
        nativeRestorePendingOnStartup: true,
        nativeRestoreSucceeded: true,
      ),
      isFalse,
    );
    expect(
      shouldOpenPanelAfterNativeRestoreAttempt(
        nativeRestorePendingOnStartup: false,
        nativeRestoreSucceeded: false,
      ),
      isFalse,
    );
  });

  test('native overlay suppresses top-layer components and controls', () {
    expect(
      shouldRenderTopLayerComponents(nativeOverlayActive: true),
      isFalse,
    );
    expect(
      shouldRenderTopLayerComponents(
        nativeOverlayActive: false,
        startupNativeRestoreInProgress: true,
      ),
      isFalse,
    );
    expect(
      shouldRenderTopLayerComponents(nativeOverlayActive: false),
      isTrue,
    );
    expect(
      shouldShowOverlayComponentControlActiveState(
        componentEnabled: true,
        nativeOverlayActive: true,
      ),
      isFalse,
    );
    expect(
      shouldShowOverlayComponentControlActiveState(
        componentEnabled: true,
        nativeOverlayActive: false,
      ),
      isTrue,
    );
    expect(
      shouldAllowOverlayComponentControl(nativeOverlayActive: true),
      isFalse,
    );
    expect(
      shouldAllowOverlayComponentControl(nativeOverlayActive: false),
      isTrue,
    );
  });

  test('paints base shader only when loaded, active, and not sandboxed', () {
    expect(
      shouldPaintBaseShader(
        shaderLoaded: true,
        sandboxActive: false,
        baseFilterEnabled: true,
      ),
      isTrue,
    );
    expect(
      shouldPaintBaseShader(
        shaderLoaded: false,
        sandboxActive: false,
        baseFilterEnabled: true,
      ),
      isFalse,
    );
    expect(
      shouldPaintBaseShader(
        shaderLoaded: true,
        sandboxActive: true,
        baseFilterEnabled: true,
      ),
      isFalse,
    );
  });

  test('base shader paint state repaints only when inputs change', () {
    const current = BaseShaderPaintState(
      width: 1920,
      height: 1080,
      brightness: 0.1,
      alpha: 0.4,
      baseColorValue: 0xFFFFB300,
    );

    expect(current.shouldRepaint(current), isFalse);
    expect(
      current.shouldRepaint(
        const BaseShaderPaintState(
          width: 1920,
          height: 1080,
          brightness: 0.1,
          alpha: 0.5,
          baseColorValue: 0xFFFFB300,
        ),
      ),
      isTrue,
    );
    expect(
      current.shouldRepaint(
        const BaseShaderPaintState(
          width: 1920,
          height: 1080,
          brightness: 0.1,
          alpha: 0.4,
          baseColorValue: 0xFF607D8B,
        ),
      ),
      isTrue,
    );
  });
}
