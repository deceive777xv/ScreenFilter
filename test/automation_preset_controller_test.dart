import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_filter_app/models/advanced_config.dart';
import 'package:screen_filter_app/services/automation_preset_controller.dart';

void main() {
  test(
    'restores the captured filter when the foreground process stops matching',
    () {
      const original = BasicFilterSnapshot(
        baseColor: Colors.black,
        alpha: 0.25,
        brightness: -0.1,
        activePreset: '自定义',
      );
      final appliedPresets = <String>[];
      final restoredSnapshots = <BasicFilterSnapshot>[];
      final controller = AutomationPresetController(
        captureCurrentFilter: () => original,
        applyPreset: appliedPresets.add,
        restoreFilter: restoredSnapshots.add,
      );
      final rules = [AutomationRule(processName: 'Code.exe', presetName: '夜间')];

      controller.update(enabled: true, rules: rules, processName: 'code.exe');
      controller.update(
        enabled: true,
        rules: rules,
        processName: 'notepad.exe',
      );

      expect(appliedPresets, ['夜间']);
      expect(restoredSnapshots, [original]);
    },
  );

  test(
    'keeps the original snapshot when switching between matching presets',
    () {
      var captureCount = 0;
      const original = BasicFilterSnapshot(
        baseColor: Colors.blue,
        alpha: 0.4,
        brightness: 0.2,
        activePreset: '护眼',
      );
      final appliedPresets = <String>[];
      final restoredSnapshots = <BasicFilterSnapshot>[];
      final controller = AutomationPresetController(
        captureCurrentFilter: () {
          captureCount++;
          return original;
        },
        applyPreset: appliedPresets.add,
        restoreFilter: restoredSnapshots.add,
      );
      final rules = [
        AutomationRule(processName: 'code.exe', presetName: '夜间'),
        AutomationRule(processName: 'devenv.exe', presetName: '护眼'),
      ];

      controller.update(enabled: true, rules: rules, processName: 'code.exe');
      controller.update(enabled: true, rules: rules, processName: 'devenv.exe');
      controller.update(
        enabled: true,
        rules: rules,
        processName: 'explorer.exe',
      );

      expect(captureCount, 1);
      expect(appliedPresets, ['夜间', '护眼']);
      expect(restoredSnapshots, [original]);
    },
  );
}
