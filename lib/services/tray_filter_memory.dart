import 'package:flutter/material.dart';

import '../models/screen_post_process_effect.dart';
import 'shader_filter_service.dart';

sealed class TrayFilterRestoreTarget {
  const TrayFilterRestoreTarget();
}

class TrayBasicFilterSnapshot extends TrayFilterRestoreTarget {
  const TrayBasicFilterSnapshot({
    required this.baseColor,
    required this.alpha,
    required this.brightness,
  });

  final Color baseColor;
  final double alpha;
  final double brightness;
}

class TrayNativeFilterSnapshot extends TrayFilterRestoreTarget {
  const TrayNativeFilterSnapshot({
    required this.mode,
    required this.origin,
    required this.accentColor,
    required this.baseColor,
    required this.alpha,
    required this.brightness,
    required this.shaderCode,
    required this.postProcessEffect,
    required this.postProcessIntensity,
  });

  final FilterApplyMode mode;
  final FilterApplyOrigin origin;
  final Color accentColor;
  final Color baseColor;
  final double alpha;
  final double brightness;
  final String? shaderCode;
  final ScreenPostProcessEffect postProcessEffect;
  final double postProcessIntensity;
}

class TrayFilterMemory {
  TrayFilterRestoreTarget? _restoreTarget;

  TrayFilterRestoreTarget? get restoreTarget => _restoreTarget;

  void rememberBasic({
    required Color baseColor,
    required double alpha,
    required double brightness,
  }) {
    if (alpha.abs() <= 0.001 && brightness.abs() <= 0.001) return;
    _restoreTarget = TrayBasicFilterSnapshot(
      baseColor: baseColor,
      alpha: alpha,
      brightness: brightness,
    );
  }

  void rememberNative({
    required FilterApplyMode mode,
    required FilterApplyOrigin origin,
    required Color accentColor,
    required Color baseColor,
    required double alpha,
    required double brightness,
    required String? shaderCode,
    required bool shaderCompiled,
    required ScreenPostProcessEffect postProcessEffect,
    required double postProcessIntensity,
  }) {
    if (mode == FilterApplyMode.none) return;
    if (origin == FilterApplyOrigin.none) return;
    if (!shaderCompiled && postProcessEffect == ScreenPostProcessEffect.none) {
      return;
    }
    _restoreTarget = TrayNativeFilterSnapshot(
      mode: mode,
      origin: origin,
      accentColor: accentColor,
      baseColor: baseColor,
      alpha: alpha,
      brightness: brightness,
      shaderCode: shaderCode,
      postProcessEffect: postProcessEffect,
      postProcessIntensity: postProcessIntensity,
    );
  }
}
