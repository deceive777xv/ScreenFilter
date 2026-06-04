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
