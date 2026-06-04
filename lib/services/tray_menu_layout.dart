enum TrayMenuAction {
  togglePanel,
  toggleFilter,
  toggleSpotlight,
  toggleHotkey,
  presets,
  applyEyeCarePreset,
  applyNightPreset,
  clearFilter,
  exit,
}

enum TrayMenuEntryKind { item, checkbox, separator, submenu }

class TrayMenuState {
  final bool panelOpen;
  final bool filterEnabled;
  final bool spotlightEnabled;
  final bool hotkeyEnabled;

  const TrayMenuState({
    required this.panelOpen,
    required this.filterEnabled,
    required this.spotlightEnabled,
    required this.hotkeyEnabled,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrayMenuState &&
          other.panelOpen == panelOpen &&
          other.filterEnabled == filterEnabled &&
          other.spotlightEnabled == spotlightEnabled &&
          other.hotkeyEnabled == hotkeyEnabled;

  @override
  int get hashCode =>
      Object.hash(panelOpen, filterEnabled, spotlightEnabled, hotkeyEnabled);
}

class TrayMenuEntry {
  final TrayMenuEntryKind kind;
  final String label;
  final TrayMenuAction? action;
  final bool checked;
  final List<TrayMenuEntry> children;

  const TrayMenuEntry._({
    required this.kind,
    required this.label,
    required this.action,
    this.checked = false,
    this.children = const [],
  });

  const TrayMenuEntry.item({
    required String label,
    required TrayMenuAction action,
  }) : this._(kind: TrayMenuEntryKind.item, label: label, action: action);

  const TrayMenuEntry.checkbox({
    required String label,
    required TrayMenuAction action,
    required bool checked,
  }) : this._(
         kind: TrayMenuEntryKind.checkbox,
         label: label,
         action: action,
         checked: checked,
       );

  const TrayMenuEntry.separator()
    : this._(kind: TrayMenuEntryKind.separator, label: '', action: null);

  const TrayMenuEntry.submenu({
    required String label,
    required TrayMenuAction action,
    required List<TrayMenuEntry> children,
  }) : this._(
         kind: TrayMenuEntryKind.submenu,
         label: label,
         action: action,
         children: children,
       );
}

List<TrayMenuEntry> buildTrayMenuEntries(TrayMenuState state) {
  return [
    TrayMenuEntry.item(
      label: state.panelOpen ? '隐藏面板' : '显示面板',
      action: TrayMenuAction.togglePanel,
    ),
    const TrayMenuEntry.separator(),
    TrayMenuEntry.checkbox(
      label: '滤镜',
      action: TrayMenuAction.toggleFilter,
      checked: state.filterEnabled,
    ),
    TrayMenuEntry.checkbox(
      label: '聚光灯',
      action: TrayMenuAction.toggleSpotlight,
      checked: state.spotlightEnabled,
    ),
    TrayMenuEntry.checkbox(
      label: '快捷键',
      action: TrayMenuAction.toggleHotkey,
      checked: state.hotkeyEnabled,
    ),
    const TrayMenuEntry.separator(),
    const TrayMenuEntry.submenu(
      label: '常用预设',
      action: TrayMenuAction.presets,
      children: [
        TrayMenuEntry.item(
          label: '护眼',
          action: TrayMenuAction.applyEyeCarePreset,
        ),
        TrayMenuEntry.item(
          label: '夜间',
          action: TrayMenuAction.applyNightPreset,
        ),
        TrayMenuEntry.item(label: '清除滤镜', action: TrayMenuAction.clearFilter),
      ],
    ),
    const TrayMenuEntry.separator(),
    const TrayMenuEntry.item(label: '退出', action: TrayMenuAction.exit),
  ];
}
