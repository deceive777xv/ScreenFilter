import 'package:flutter_test/flutter_test.dart';
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
}
