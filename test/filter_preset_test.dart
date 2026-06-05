import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_filter_app/models/filter_preset.dart';

void main() {
  test('preview color mirrors shader brightness and alpha composition', () {
    const preset = FilterPreset(
      name: '测试',
      description: '测试预设',
      icon: Icons.filter_alt_outlined,
      baseColor: Color(0xFF000000),
      alpha: 0.24,
      brightness: -0.16,
      tileColor: Color(0xFFE5E7EB),
    );

    expect(preset.effectiveOverlayAlpha, closeTo(0.3616, 0.0001));
    expect(preset.effectiveOverlayColor.toARGB32(), 0x5C000000);
  });

  test('built-in presets keep visual strength in comfortable bands', () {
    final presets = {
      for (final preset in kBasicFilterPresets) preset.name: preset,
    };

    expect(presets['护眼']!.effectiveOverlayAlpha, lessThan(0.16));
    expect(presets['电子书']!.effectiveOverlayAlpha, lessThan(0.18));
    expect(presets['夜间']!.effectiveOverlayAlpha, inInclusiveRange(0.32, 0.38));
    expect(presets['专注']!.effectiveOverlayAlpha, inInclusiveRange(0.24, 0.30));
    expect(
      presets['低蓝光']!.effectiveOverlayAlpha,
      greaterThan(presets['护眼']!.effectiveOverlayAlpha),
    );
  });

  test('color vision presets do not overpromise calibration behavior', () {
    final presets = {
      for (final preset in kBasicFilterPresets) preset.name: preset,
    };

    expect(presets['红绿色弱']!.description, contains('不替代'));
    expect(presets['蓝黄色弱']!.description, contains('不替代'));
  });
}
