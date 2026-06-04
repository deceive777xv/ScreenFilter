import 'package:flutter/material.dart';

import '../models/advanced_config.dart';

class BasicFilterSnapshot {
  const BasicFilterSnapshot({
    required this.baseColor,
    required this.alpha,
    required this.brightness,
    required this.activePreset,
  });

  final Color baseColor;
  final double alpha;
  final double brightness;
  final String? activePreset;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BasicFilterSnapshot &&
          other.baseColor == baseColor &&
          other.alpha == alpha &&
          other.brightness == brightness &&
          other.activePreset == activePreset;

  @override
  int get hashCode => Object.hash(baseColor, alpha, brightness, activePreset);
}

class AutomationPresetController {
  AutomationPresetController({
    required this.captureCurrentFilter,
    required this.applyPreset,
    required this.restoreFilter,
  });

  final BasicFilterSnapshot Function() captureCurrentFilter;
  final void Function(String presetName) applyPreset;
  final void Function(BasicFilterSnapshot snapshot) restoreFilter;

  BasicFilterSnapshot? _snapshotBeforeAutomation;
  String? _lastMatchedPreset;

  void update({
    required bool enabled,
    required List<AutomationRule> rules,
    required String? processName,
  }) {
    if (!enabled || rules.isEmpty) {
      reset(restore: true);
      return;
    }
    if (processName == null) return;

    final matchedPreset = _matchPreset(rules, processName);
    if (matchedPreset == null) {
      reset(restore: true);
      return;
    }

    _snapshotBeforeAutomation ??= captureCurrentFilter();
    if (_lastMatchedPreset == matchedPreset) return;

    _lastMatchedPreset = matchedPreset;
    applyPreset(matchedPreset);
  }

  void reset({required bool restore}) {
    final snapshot = _snapshotBeforeAutomation;
    _snapshotBeforeAutomation = null;
    _lastMatchedPreset = null;
    if (restore && snapshot != null) {
      restoreFilter(snapshot);
    }
  }

  String? _matchPreset(List<AutomationRule> rules, String processName) {
    final lowerProcess = processName.toLowerCase();
    for (final rule in rules) {
      if (!rule.enabled) continue;
      if (lowerProcess == rule.processName.toLowerCase()) {
        return rule.presetName;
      }
    }
    return null;
  }
}
