import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_filter_app/models/screen_post_process_effect.dart';
import 'package:screen_filter_app/services/shader_filter_service.dart';
import 'package:screen_filter_app/services/tray_filter_memory.dart';
import 'package:screen_filter_app/services/tray_menu_layout.dart';

void main() {
  test('builds a concise grouped tray menu', () {
    final entries = buildTrayMenuEntries(
      const TrayMenuState(
        panelOpen: false,
        filterEnabled: false,
        spotlightEnabled: false,
        hotkeyEnabled: true,
      ),
    );

    expect(entries.map((entry) => entry.label).toList(), [
      '显示面板',
      '',
      '滤镜',
      '聚光灯',
      '快捷键',
      '',
      '常用预设',
      '',
      '退出',
    ]);

    final presetMenu = entries.firstWhere(
      (entry) => entry.action == TrayMenuAction.presets,
    );
    expect(presetMenu.kind, TrayMenuEntryKind.submenu);
    expect(presetMenu.children.map((entry) => entry.label).toList(), [
      '护眼',
      '夜间',
      '清除滤镜',
    ]);
  });

  test('reflects panel, filter, and spotlight states', () {
    final entries = buildTrayMenuEntries(
      const TrayMenuState(
        panelOpen: true,
        filterEnabled: true,
        spotlightEnabled: true,
        hotkeyEnabled: true,
      ),
    );

    final panel = entries.firstWhere(
      (entry) => entry.action == TrayMenuAction.togglePanel,
    );
    final filter = entries.firstWhere(
      (entry) => entry.action == TrayMenuAction.toggleFilter,
    );
    final spotlight = entries.firstWhere(
      (entry) => entry.action == TrayMenuAction.toggleSpotlight,
    );
    final hotkey = entries.firstWhere(
      (entry) => entry.action == TrayMenuAction.toggleHotkey,
    );

    expect(panel.label, '隐藏面板');
    expect(filter.kind, TrayMenuEntryKind.checkbox);
    expect(filter.checked, isTrue);
    expect(spotlight.kind, TrayMenuEntryKind.checkbox);
    expect(spotlight.checked, isTrue);
    expect(hotkey.kind, TrayMenuEntryKind.checkbox);
    expect(hotkey.checked, isTrue);
  });

  test('restores the last native mosaic filter before basic fallback', () {
    final memory = TrayFilterMemory();

    memory.rememberBasic(baseColor: Colors.amber, alpha: 0.2, brightness: -0.1);
    memory.rememberNative(
      mode: FilterApplyMode.dynamic,
      accentColor: Colors.white,
      baseColor: Colors.transparent,
      alpha: 1.0,
      brightness: 0.0,
      shaderCompiled: false,
      postProcessEffect: ScreenPostProcessEffect.mosaic,
      postProcessIntensity: 24.0,
    );

    final restore = memory.restoreTarget;

    expect(restore, isA<TrayNativeFilterSnapshot>());
    final native = restore as TrayNativeFilterSnapshot;
    expect(native.mode, FilterApplyMode.dynamic);
    expect(native.postProcessEffect, ScreenPostProcessEffect.mosaic);
    expect(native.postProcessIntensity, 24.0);
    expect(native.alpha, 1.0);
  });

  test('restores basic filter when the last remembered filter was basic', () {
    final memory = TrayFilterMemory();

    memory.rememberNative(
      mode: FilterApplyMode.dynamic,
      accentColor: Colors.white,
      baseColor: Colors.transparent,
      alpha: 1.0,
      brightness: 0.0,
      shaderCompiled: false,
      postProcessEffect: ScreenPostProcessEffect.mosaic,
      postProcessIntensity: 24.0,
    );
    memory.rememberBasic(
      baseColor: Colors.orange,
      alpha: 0.3,
      brightness: -0.2,
    );

    final restore = memory.restoreTarget;

    expect(restore, isA<TrayBasicFilterSnapshot>());
    final basic = restore as TrayBasicFilterSnapshot;
    expect(basic.baseColor, Colors.orange);
    expect(basic.alpha, 0.3);
    expect(basic.brightness, -0.2);
  });
}
