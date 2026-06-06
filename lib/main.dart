import 'dart:async';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:system_tray/system_tray.dart';
import 'dart:io' show Platform, exit;
import 'dart:ui' as ui;
import 'ui/console_panel.dart';
import 'ui/overlays/clock_overlay.dart';
import 'ui/overlays/slogan_overlay.dart';
import 'ui/overlays/watermark_overlay.dart';
import 'ui/overlays/focus_mode_overlay.dart';
import 'ui/overlays/spotlight_overlay.dart';
import 'ui/overlays/region_mask_clipper.dart';
import 'ui/overlays/region_mask_drawing_overlay.dart';
import 'models/overlay_component.dart';
import 'models/advanced_config.dart';
import 'models/filter_preset.dart';
import 'models/screen_post_process_effect.dart';
import 'services/automation_preset_controller.dart';
import 'services/console_hotkey_service.dart';
import 'services/debounced_action.dart';
import 'services/filter_overlay_logic.dart';
import 'services/fullscreen_window_refresh.dart';
import 'services/keyed_debounced_action.dart';
import 'services/settings_service.dart';
import 'services/shader_filter_service.dart';
import 'services/tray_filter_memory.dart';
import 'services/tray_menu_layout.dart';
import 'services/win32_polling_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  final settingsService = await SettingsService.init();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(800, 600),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: true,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.setFullScreen(true);
    await refreshFullscreenWindowMetrics();
    await windowManager.setIgnoreMouseEvents(true);
  });

  runApp(ScreenFilterApp(settingsService: settingsService));
}

class ScreenFilterApp extends StatefulWidget {
  final SettingsService settingsService;
  const ScreenFilterApp({super.key, required this.settingsService});

  @override
  State<ScreenFilterApp> createState() => _ScreenFilterAppState();
}

class _ScreenFilterAppState extends State<ScreenFilterApp> {
  late String _fontFamily;

  @override
  void initState() {
    super.initState();
    _fontFamily = widget.settingsService.getFontFamily();
  }

  void _onFontFamilyChanged(String font) {
    setState(() => _fontFamily = font);
    widget.settingsService.setFontFamily(font);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: _fontFamily,
        fontFamilyFallback: const ['SimHei', 'sans-serif'],
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: Colors.transparent,
        sliderTheme: const SliderThemeData(
          activeTrackColor: Color(0xFF3B82F6),
          thumbColor: Color(0xFF3B82F6),
          overlayColor: Color(0x1A3B82F6),
          inactiveTrackColor: Color(0xFFE5E7EB),
          trackHeight: 3,
        ),
      ),
      home: FilterOverlayPage(
        settingsService: widget.settingsService,
        onFontFamilyChanged: _onFontFamilyChanged,
      ),
    );
  }
}

class FilterOverlayPage extends StatefulWidget {
  final SettingsService settingsService;
  final Function(String) onFontFamilyChanged;
  const FilterOverlayPage({
    super.key,
    required this.settingsService,
    required this.onFontFamilyChanged,
  });

  @override
  State<FilterOverlayPage> createState() => _FilterOverlayPageState();
}

class _FilterOverlayPageState extends State<FilterOverlayPage> {
  late double _brightness;
  late double _alpha;
  late Color _baseColor;
  bool _isPanelOpen = false;

  ui.FragmentShader? _shader;

  final SystemTray _systemTray = SystemTray();
  bool _systemTrayReady = false;

  // 沙盒自定义滤镜
  late final Win32PollingService _win32PollingService;
  late final ShaderFilterService _shaderFilterService;

  // 顶层组件
  late OverlayComponent _clockComponent;
  late OverlayComponent _sloganComponent;
  late OverlayComponent _watermarkComponent;

  // 高级功能
  late FocusModeConfig _focusModeConfig;
  late SpotlightConfig _spotlightConfig;
  late RegionMaskConfig _regionMaskConfig;
  late List<AutomationRule> _automationRules;
  late bool _automationEnabled;
  late ConsoleHotkeyConfig _consoleHotkeyConfig;
  Win32PollingRelease? _automationPollingRelease;
  late final AutomationPresetController _automationPresetController;
  late final ConsoleHotkeyService _consoleHotkeyService;
  bool _isDrawingRegion = false;
  final TrayFilterMemory _trayFilterMemory = TrayFilterMemory();
  late final DebouncedAction _basicFilterPersistDebouncer;
  late final DebouncedAction _trayMenuRefreshDebouncer;
  late final KeyedDebouncedAction<String> _settingsPersistDebouncer;
  TrayMenuState? _lastAppliedTrayMenuState;

  SettingsService get _settings => widget.settingsService;

  @override
  void initState() {
    super.initState();
    // 从持久化加载
    _brightness = _settings.getBrightness();
    _alpha = _settings.getAlpha();
    _baseColor = _settings.getBaseColor();

    // 加载顶层组件
    _clockComponent = _settings.getOverlayComponent(OverlayType.clock);
    _sloganComponent = _settings.getOverlayComponent(OverlayType.slogan);
    _watermarkComponent = _settings.getOverlayComponent(OverlayType.watermark);

    // 加载高级功能
    _focusModeConfig = _settings.getFocusModeConfig();
    _spotlightConfig = _settings.getSpotlightConfig();
    _regionMaskConfig = _settings.getRegionMaskConfig();
    _automationRules = _settings.getAutomationRules();
    _automationEnabled = _settings.getAutomationEnabled();
    _consoleHotkeyConfig = _settings.getConsoleHotkeyConfig();
    _basicFilterPersistDebouncer = DebouncedAction(
      delay: const Duration(milliseconds: 250),
    );
    _trayMenuRefreshDebouncer = DebouncedAction(
      delay: const Duration(milliseconds: 120),
    );
    _settingsPersistDebouncer = KeyedDebouncedAction<String>(
      delay: const Duration(milliseconds: 250),
    );
    _automationPresetController = AutomationPresetController(
      captureCurrentFilter: _captureBasicFilterSnapshot,
      applyPreset: _applyPresetByName,
      restoreFilter: _restoreBasicFilterSnapshot,
    );
    _consoleHotkeyService = ConsoleHotkeyService(onPressed: _togglePanel);

    // Init Win32 polling and shader filter services
    _win32PollingService = Win32PollingService();
    _shaderFilterService = ShaderFilterService(
      win32PollingService: _win32PollingService,
    );
    _shaderFilterService.init();
    _shaderFilterService.modeNotifier.addListener(_onSandboxModeChanged);

    initSystemTray();
    _loadShader();

    // Start automation if enabled
    if (_automationEnabled) _startAutomation();
    unawaited(_consoleHotkeyService.apply(_consoleHotkeyConfig));
  }

  void _onSandboxModeChanged() {
    // 沙盒/特效激活时，若当前 alpha 为 0（清除状态），自动提升到 1.0 以确保可见
    if (_shaderFilterService.mode != FilterApplyMode.none && _alpha == 0.0) {
      _alpha = 1.0;
      _settings.setAlpha(_alpha);
      _shaderFilterService.updateFilterVisuals(
        opacity: _alpha,
        brightness: _brightness,
      );
    }
    setState(() {});
    _scheduleTrayMenuRefresh();
  }

  @override
  void dispose() {
    _basicFilterPersistDebouncer.flush();
    _settingsPersistDebouncer.flush();
    _trayMenuRefreshDebouncer.dispose();
    _automationPollingRelease?.call();
    unawaited(_consoleHotkeyService.dispose());
    _shaderFilterService.modeNotifier.removeListener(_onSandboxModeChanged);
    _shaderFilterService.dispose();
    _win32PollingService.dispose();
    _systemTray.destroy();
    _basicFilterPersistDebouncer.dispose();
    _settingsPersistDebouncer.dispose();
    super.dispose();
  }

  Future<void> _loadShader() async {
    try {
      ui.FragmentProgram program = await ui.FragmentProgram.fromAsset(
        'shaders/filter.frag',
      );
      setState(() {
        _shader = program.fragmentShader();
      });
    } catch (e) {
      debugPrint('Error loading shader: $e');
    }
  }

  Future<void> initSystemTray() async {
    String path = Platform.isWindows
        ? 'assets/screenfilter_icon.ico'
        : 'assets/screenfilter_icon.png';
    try {
      await _systemTray.initSystemTray(
        title: 'Filter',
        iconPath: path,
        toolTip: '滤镜 - 点击打开设置',
      );

      await _setTrayContextMenu(force: true);
      _systemTrayReady = true;

      _systemTray.registerSystemTrayEventHandler((eventName) async {
        if (eventName == kSystemTrayEventClick) {
          _togglePanel();
        } else if (eventName == kSystemTrayEventRightClick) {
          await _showTrayMenu();
        }
      });
    } catch (e) {
      debugPrint('Tray Error: $e');
    }
  }

  void _togglePanel() async {
    if (_isPanelOpen) {
      setState(() => _isPanelOpen = false);
      await windowManager.setIgnoreMouseEvents(true);
    } else {
      await refreshFullscreenWindowMetrics();
      if (!mounted) return;
      setState(() => _isPanelOpen = true);
      await windowManager.setIgnoreMouseEvents(false);
    }
    _scheduleTrayMenuRefresh();
  }

  bool get _baseFilterEnabled =>
      _alpha.abs() > 0.001 || _brightness.abs() > 0.001;
  bool get _filterEnabled =>
      _baseFilterEnabled || _shaderFilterService.mode != FilterApplyMode.none;

  TrayMenuState get _trayMenuState => TrayMenuState(
    panelOpen: _isPanelOpen,
    filterEnabled: _filterEnabled,
    spotlightEnabled: _spotlightConfig.enabled,
    hotkeyEnabled: _consoleHotkeyConfig.enabled,
  );

  Future<void> _showTrayMenu() async {
    await _setTrayContextMenu(force: true);
    await _systemTray.popUpContextMenu();
  }

  void _scheduleTrayMenuRefresh() {
    if (!_systemTrayReady) return;
    _trayMenuRefreshDebouncer.schedule(() {
      unawaited(_refreshTrayMenu());
    });
  }

  Future<void> _refreshTrayMenu({bool force = false}) async {
    if (!_systemTrayReady) return;
    await _setTrayContextMenu(force: force);
  }

  Future<void> _setTrayContextMenu({bool force = false}) async {
    try {
      final state = _trayMenuState;
      if (!force && state == _lastAppliedTrayMenuState) return;
      final menu = Menu();
      await menu.buildFrom(
        _buildNativeTrayMenuItems(buildTrayMenuEntries(state)),
      );
      await _systemTray.setContextMenu(menu);
      _lastAppliedTrayMenuState = state;
    } catch (e) {
      debugPrint('Tray Menu Error: $e');
    }
  }

  List<MenuItemBase> _buildNativeTrayMenuItems(List<TrayMenuEntry> entries) {
    return entries.map((entry) {
      switch (entry.kind) {
        case TrayMenuEntryKind.item:
          return MenuItemLabel(
            label: entry.label,
            onClicked: (_) => _handleTrayAction(entry.action),
          );
        case TrayMenuEntryKind.checkbox:
          return MenuItemCheckbox(
            label: entry.label,
            checked: entry.checked,
            onClicked: (_) => _handleTrayAction(entry.action),
          );
        case TrayMenuEntryKind.separator:
          return MenuSeparator();
        case TrayMenuEntryKind.submenu:
          return SubMenu(
            label: entry.label,
            children: _buildNativeTrayMenuItems(entry.children),
          );
      }
    }).toList();
  }

  void _handleTrayAction(TrayMenuAction? action) {
    switch (action) {
      case TrayMenuAction.togglePanel:
        _togglePanel();
        break;
      case TrayMenuAction.toggleFilter:
        _toggleTrayFilter();
        break;
      case TrayMenuAction.toggleSpotlight:
        _toggleTraySpotlight();
        break;
      case TrayMenuAction.toggleHotkey:
        _toggleTrayHotkey();
        break;
      case TrayMenuAction.applyEyeCarePreset:
        _applyPresetByName('护眼');
        break;
      case TrayMenuAction.applyNightPreset:
        _applyPresetByName('夜间');
        break;
      case TrayMenuAction.clearFilter:
        _clearTrayFilter(rememberCurrent: true);
        break;
      case TrayMenuAction.exit:
        _exitFromTray();
        break;
      case TrayMenuAction.presets:
      case null:
        break;
    }
    _scheduleTrayMenuRefresh();
  }

  void _toggleTrayFilter() {
    if (_filterEnabled) {
      _clearTrayFilter(rememberCurrent: true);
      return;
    }

    final restoreTarget = _trayFilterMemory.restoreTarget;
    if (restoreTarget is TrayNativeFilterSnapshot &&
        _restoreNativeTrayFilter(restoreTarget)) {
      return;
    }
    if (restoreTarget is TrayBasicFilterSnapshot) {
      _applyBasicFilterValues(
        baseColor: restoreTarget.baseColor,
        alpha: restoreTarget.alpha,
        brightness: restoreTarget.brightness,
        activePreset: null,
      );
      return;
    }

    _applyPresetByName('护眼');
  }

  void _toggleTraySpotlight() {
    final nextEnabled = !_spotlightConfig.enabled;
    setState(() {
      _spotlightConfig = _spotlightConfig.copyWith(enabled: nextEnabled);
      if (nextEnabled && _focusModeConfig.enabled) {
        _focusModeConfig = _focusModeConfig.copyWith(enabled: false);
      }
    });
    _scheduleSpotlightConfigPersist();
    if (nextEnabled) {
      _scheduleFocusModeConfigPersist();
    }
    _scheduleTrayMenuRefresh();
  }

  void _toggleTrayHotkey() {
    _onConsoleHotkeyChanged(
      _consoleHotkeyConfig.copyWith(enabled: !_consoleHotkeyConfig.enabled),
    );
  }

  void _clearTrayFilter({required bool rememberCurrent}) {
    if (rememberCurrent) {
      if (_shaderFilterService.mode != FilterApplyMode.none) {
        _rememberCurrentNativeFilter();
      } else {
        _rememberCurrentBaseFilter();
      }
    }
    if (_shaderFilterService.mode != FilterApplyMode.none) {
      _shaderFilterService.stopFilter();
    }
    _applyBasicFilterValues(
      baseColor: Colors.transparent,
      alpha: 0.0,
      brightness: 0.0,
      activePreset: null,
      stopShaderFilter: false,
    );
  }

  void _rememberCurrentBaseFilter() {
    _trayFilterMemory.rememberBasic(
      baseColor: _baseColor,
      alpha: _alpha,
      brightness: _brightness,
    );
  }

  void _rememberCurrentNativeFilter() {
    _trayFilterMemory.rememberNative(
      mode: _shaderFilterService.mode,
      accentColor: _shaderFilterService.accentColor,
      baseColor: _baseColor,
      alpha: _alpha,
      brightness: _brightness,
      shaderCompiled: _shaderFilterService.isShaderCompiled,
      postProcessEffect: _shaderFilterService.postProcessEffect,
      postProcessIntensity: _shaderFilterService.postProcessIntensity,
    );
  }

  bool _restoreNativeTrayFilter(TrayNativeFilterSnapshot snapshot) {
    if (snapshot.postProcessEffect == ScreenPostProcessEffect.none &&
        !_shaderFilterService.isShaderCompiled) {
      return false;
    }

    final media = MediaQuery.of(context);
    _applyBasicFilterValues(
      baseColor: snapshot.baseColor,
      alpha: snapshot.alpha,
      brightness: snapshot.brightness,
      activePreset: null,
      stopShaderFilter: false,
    );
    _shaderFilterService.updateScreenSize(media.size);
    _shaderFilterService.updateDevicePixelRatio(media.devicePixelRatio);
    _shaderFilterService.updateAccentColor(snapshot.accentColor);
    _shaderFilterService.applyFilter(
      snapshot.mode,
      media.size,
      snapshot.accentColor,
      postProcessEffect: snapshot.postProcessEffect,
      postProcessIntensity: snapshot.postProcessIntensity,
    );
    return true;
  }

  void _applyBasicFilterValues({
    required Color baseColor,
    required double alpha,
    required double brightness,
    required String? activePreset,
    bool stopShaderFilter = true,
  }) {
    if (stopShaderFilter && _shaderFilterService.mode != FilterApplyMode.none) {
      _shaderFilterService.stopFilter();
    }
    setState(() {
      _baseColor = baseColor;
      _alpha = alpha;
      _brightness = brightness;
    });
    _persistBasicFilterNow(
      activePreset: activePreset,
      includeActivePreset: true,
    );
    _shaderFilterService.updateFilterVisuals(
      opacity: _alpha,
      brightness: _brightness,
    );
  }

  void _exitFromTray() {
    _basicFilterPersistDebouncer.flush();
    _settingsPersistDebouncer.flush();
    unawaited(_consoleHotkeyService.dispose());
    _shaderFilterService.dispose();
    _systemTray.destroy();
    exit(0);
  }

  void _onOverlayChanged(OverlayComponent component) {
    setState(() {});
    _scheduleOverlayComponentPersist(component);
  }

  // ── 高级功能回调 ──────────────────────────────────────────────

  void _onFocusModeChanged(FocusModeConfig config) {
    setState(() => _focusModeConfig = config);
    _scheduleFocusModeConfigPersist();
    _scheduleTrayMenuRefresh();
  }

  void _onSpotlightChanged(SpotlightConfig config) {
    setState(() => _spotlightConfig = config);
    _scheduleSpotlightConfigPersist();
    _scheduleTrayMenuRefresh();
  }

  void _onRegionMaskChanged(RegionMaskConfig config) {
    setState(() => _regionMaskConfig = config);
    _scheduleRegionMaskConfigPersist();
    _shaderFilterService.updateRegionMask(config);
  }

  void _startDrawingRegion() {
    setState(() {
      _isDrawingRegion = true;
      _isPanelOpen = false;
    });
    windowManager.setIgnoreMouseEvents(false);
    _scheduleTrayMenuRefresh();
  }

  void _onDrawingComplete(List<Offset> polygon) {
    final newRegion = MaskRegion(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: '区域 ${_regionMaskConfig.regions.length + 1}',
      points: polygon,
    );
    setState(() {
      _isDrawingRegion = false;
      _regionMaskConfig.regions = [..._regionMaskConfig.regions, newRegion];
      _isPanelOpen = true;
    });
    _scheduleRegionMaskConfigPersist();
    _shaderFilterService.updateRegionMask(_regionMaskConfig);
    _scheduleTrayMenuRefresh();
  }

  void _onDrawingCancel() {
    setState(() {
      _isDrawingRegion = false;
      _isPanelOpen = true;
    });
    _scheduleTrayMenuRefresh();
  }

  void _onAutomationRulesChanged(List<AutomationRule> rules) {
    setState(() => _automationRules = rules);
    _settings.setAutomationRules(rules);
    if (_automationEnabled) {
      _checkAutomationRules(_win32PollingService.foregroundProcessName.value);
    }
  }

  void _onAutomationEnabledChanged(bool enabled) {
    setState(() => _automationEnabled = enabled);
    _settings.setAutomationEnabled(enabled);
    if (enabled) {
      _startAutomation();
    } else {
      _stopAutomation();
    }
  }

  void _onConsoleHotkeyChanged(ConsoleHotkeyConfig config) {
    setState(() => _consoleHotkeyConfig = config);
    _settings.setConsoleHotkeyConfig(config);
    unawaited(_consoleHotkeyService.apply(config));
    _scheduleTrayMenuRefresh();
  }

  void _startAutomation() {
    _automationPollingRelease?.call();
    _automationPollingRelease = _win32PollingService
        .addForegroundProcessNameListener(() {
          _checkAutomationRules(
            _win32PollingService.foregroundProcessName.value,
          );
        });
    _checkAutomationRules(_win32PollingService.foregroundProcessName.value);
  }

  void _stopAutomation() {
    _automationPollingRelease?.call();
    _automationPollingRelease = null;
    _automationPresetController.reset(restore: true);
  }

  void _checkAutomationRules(String? processName) {
    _automationPresetController.update(
      enabled: _automationEnabled,
      rules: _automationRules,
      processName: processName,
    );
  }

  void _applyPresetByName(String name) {
    final match = kBasicFilterPresets.where((p) => p.name == name).firstOrNull;
    if (match == null) return;
    _applyBasicFilterValues(
      baseColor: match.baseColor,
      alpha: match.alpha,
      brightness: match.brightness,
      activePreset: name,
    );
    if (match.alpha.abs() > 0.001 || match.brightness.abs() > 0.001) {
      _rememberCurrentBaseFilter();
    }
    _scheduleTrayMenuRefresh();
  }

  void _onConfigImported(AppConfig config) {
    // Reload all state from the imported config
    setState(() {
      _brightness = config.brightness;
      _alpha = config.alpha;
      _baseColor = config.baseColor;
      _focusModeConfig = config.focusMode;
      _spotlightConfig = config.spotlight;
      _regionMaskConfig = config.regionMask;
      _automationRules = config.automationRules;
      _automationEnabled = config.automationEnabled;
      _consoleHotkeyConfig = config.consoleHotkey;
    });
    _shaderFilterService.updateRegionMask(_regionMaskConfig);
    unawaited(_consoleHotkeyService.apply(_consoleHotkeyConfig));
    _automationPresetController.reset(restore: false);
    if (_automationEnabled) {
      _startAutomation();
    } else {
      _stopAutomation();
    }
    _scheduleTrayMenuRefresh();
  }

  BasicFilterSnapshot _captureBasicFilterSnapshot() {
    return BasicFilterSnapshot(
      baseColor: _baseColor,
      alpha: _alpha,
      brightness: _brightness,
      activePreset: _settings.getActivePreset(),
    );
  }

  void _restoreBasicFilterSnapshot(BasicFilterSnapshot snapshot) {
    _applyBasicFilterValues(
      baseColor: snapshot.baseColor,
      alpha: snapshot.alpha,
      brightness: snapshot.brightness,
      activePreset: snapshot.activePreset,
    );
    _scheduleTrayMenuRefresh();
  }

  void _persistBasicFilterNow({
    String? activePreset,
    bool includeActivePreset = false,
  }) {
    _basicFilterPersistDebouncer.cancel();
    unawaited(
      _saveBasicFilter(
        activePreset: activePreset,
        includeActivePreset: includeActivePreset,
      ),
    );
  }

  void _scheduleBasicFilterPersist() {
    _basicFilterPersistDebouncer.schedule(() {
      unawaited(_saveBasicFilter());
    });
  }

  Future<void> _saveBasicFilter({
    String? activePreset,
    bool includeActivePreset = false,
  }) async {
    await Future.wait([
      _settings.setBaseColor(_baseColor),
      _settings.setAlpha(_alpha),
      _settings.setBrightness(_brightness),
      if (includeActivePreset) _settings.setActivePreset(activePreset),
    ]);
  }

  void _scheduleOverlayComponentPersist(OverlayComponent component) {
    _settingsPersistDebouncer.schedule('overlay:${component.type.name}', () {
      unawaited(_settings.setOverlayComponent(component));
    });
  }

  void _scheduleFocusModeConfigPersist() {
    _settingsPersistDebouncer.schedule('advanced:focus', () {
      unawaited(_settings.setFocusModeConfig(_focusModeConfig));
    });
  }

  void _scheduleSpotlightConfigPersist() {
    _settingsPersistDebouncer.schedule('advanced:spotlight', () {
      unawaited(_settings.setSpotlightConfig(_spotlightConfig));
    });
  }

  void _scheduleRegionMaskConfigPersist() {
    _settingsPersistDebouncer.schedule('advanced:region-mask', () {
      unawaited(_settings.setRegionMaskConfig(_regionMaskConfig));
    });
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    _shaderFilterService.updateScreenSize(MediaQuery.of(context).size);
    _shaderFilterService.updateDevicePixelRatio(
      MediaQuery.of(context).devicePixelRatio,
    );
    _shaderFilterService.updateFilterVisuals(
      opacity: _alpha,
      brightness: _brightness,
    );
    final dpr = MediaQuery.of(context).devicePixelRatio;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // 滤镜层（受区域遮罩裁剪）
          IgnorePointer(
            ignoring: true,
            child: RegionMaskClipper(
              enabled: _regionMaskConfig.enabled,
              regions: _regionMaskConfig.regions,
              inverted: _regionMaskConfig.inverted,
              child: Stack(
                children: [
                  // 基础 GLSL 滤镜
                  _buildShaderFilter(),
                  // 沙盒自定义滤镜叠加层
                  ValueListenableBuilder<ui.Image?>(
                    valueListenable: _shaderFilterService.filterImageNotifier,
                    builder: (context, image, _) {
                      if (image == null ||
                          _shaderFilterService.mode == FilterApplyMode.none) {
                        return const SizedBox();
                      }
                      Widget child = SizedBox.expand(
                        child: RawImage(image: image, fit: BoxFit.cover),
                      );
                      if (_brightness != 0) {
                        child = ColorFiltered(
                          colorFilter: ColorFilter.matrix(
                            _makeBrightnessMatrix(_brightness),
                          ),
                          child: child,
                        );
                      }
                      return Opacity(
                        opacity: _alpha.clamp(0.0, 1.0),
                        child: child,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          // 专注模式覆盖层
          IgnorePointer(
            ignoring: true,
            child: FocusModeOverlay(
              enabled: _focusModeConfig.enabled,
              win32PollingService: _win32PollingService,
              dimOpacity: _focusModeConfig.dimOpacity,
              borderRadius: _focusModeConfig.borderRadius,
              devicePixelRatio: dpr,
            ),
          ),
          // 聚光灯覆盖层
          IgnorePointer(
            ignoring: true,
            child: SpotlightOverlay(
              enabled: _spotlightConfig.enabled,
              win32PollingService: _win32PollingService,
              radius: _spotlightConfig.radius,
              dimOpacity: _spotlightConfig.dimOpacity,
              softEdge: _spotlightConfig.softEdge,
              devicePixelRatio: dpr,
            ),
          ),
          // 顶层组件（面板关闭时不可交互）
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_isPanelOpen,
              child: Stack(
                children: [
                  ClockOverlay(
                    component: _clockComponent,
                    draggable: _isPanelOpen,
                    onPositionChanged: (pos) {
                      setState(() => _clockComponent.position = pos);
                      _scheduleOverlayComponentPersist(_clockComponent);
                    },
                  ),
                  SloganOverlay(
                    component: _sloganComponent,
                    draggable: _isPanelOpen,
                    onPositionChanged: (pos) {
                      setState(() => _sloganComponent.position = pos);
                      _scheduleOverlayComponentPersist(_sloganComponent);
                    },
                  ),
                  WatermarkOverlay(
                    component: _watermarkComponent,
                    draggable: _isPanelOpen,
                    onPositionChanged: (pos) {
                      setState(() => _watermarkComponent.position = pos);
                      _scheduleOverlayComponentPersist(_watermarkComponent);
                    },
                  ),
                ],
              ),
            ),
          ),
          if (_isPanelOpen) Center(child: _buildPanel()),
          // 区域遮罩绘制模式
          if (_isDrawingRegion)
            RegionMaskDrawingOverlay(
              onComplete: _onDrawingComplete,
              onCancel: _onDrawingCancel,
            ),
        ],
      ),
    );
  }

  static List<double> _makeBrightnessMatrix(double brightness) {
    if (brightness <= 0) {
      final s = 1.0 + brightness * 0.95;
      return [s, 0, 0, 0, 0, 0, s, 0, 0, 0, 0, 0, s, 0, 0, 0, 0, 0, 1, 0];
    } else {
      final s = 1.0 - brightness * 0.95;
      final o = brightness * 0.95 * 255;
      return [s, 0, 0, 0, o, 0, s, 0, 0, o, 0, 0, s, 0, o, 0, 0, 0, 1, 0];
    }
  }

  Widget _buildShaderFilter() {
    final sandboxActive = _shaderFilterService.mode != FilterApplyMode.none;
    // 当沙盒/特效激活时，GLSL层全透明无需渲染，直接跳过以避免干扰DX11叠加层
    if (!shouldPaintBaseShader(
      shaderLoaded: _shader != null,
      sandboxActive: sandboxActive,
      baseFilterEnabled: _baseFilterEnabled,
    )) {
      return const SizedBox();
    }

    return Builder(
      builder: (context) {
        final size = MediaQuery.of(context).size;
        final paintState = BaseShaderPaintState(
          width: size.width,
          height: size.height,
          brightness: _brightness,
          alpha: _alpha,
          baseColorValue: _baseColor.toARGB32(),
        );

        _shader!.setFloat(0, paintState.width);
        _shader!.setFloat(1, paintState.height);
        _shader!.setFloat(2, paintState.brightness);
        _shader!.setFloat(3, paintState.alpha);
        _shader!.setFloat(4, _baseColor.r);
        _shader!.setFloat(5, _baseColor.g);
        _shader!.setFloat(6, _baseColor.b);
        _shader!.setFloat(7, _baseColor.a);

        return CustomPaint(
          size: Size.infinite,
          painter: ShaderPainter(shader: _shader!, state: paintState),
        );
      },
    );
  }

  Widget _buildPanel() {
    return ConsolePanel(
      brightness: _brightness,
      alpha: _alpha,
      baseColor: _baseColor,
      settingsService: _settings,
      clockComponent: _clockComponent,
      sloganComponent: _sloganComponent,
      watermarkComponent: _watermarkComponent,
      onOverlayChanged: _onOverlayChanged,
      shaderFilterService: _shaderFilterService,
      focusModeConfig: _focusModeConfig,
      spotlightConfig: _spotlightConfig,
      automationRules: _automationRules,
      automationEnabled: _automationEnabled,
      consoleHotkeyConfig: _consoleHotkeyConfig,
      onFocusModeChanged: _onFocusModeChanged,
      onSpotlightChanged: _onSpotlightChanged,
      onConsoleHotkeyChanged: _onConsoleHotkeyChanged,
      regionMaskConfig: _regionMaskConfig,
      onRegionMaskChanged: _onRegionMaskChanged,
      onStartDrawingRegion: _startDrawingRegion,
      onAutomationRulesChanged: _onAutomationRulesChanged,
      onAutomationEnabledChanged: _onAutomationEnabledChanged,
      onConfigImported: _onConfigImported,
      onBrightnessChanged: (v) {
        setState(() => _brightness = v);
        _scheduleBasicFilterPersist();
        _shaderFilterService.updateFilterVisuals(
          opacity: _alpha,
          brightness: _brightness,
        );
        _rememberCurrentBaseFilter();
        _scheduleTrayMenuRefresh();
      },
      onAlphaChanged: (v) {
        setState(() => _alpha = v);
        _scheduleBasicFilterPersist();
        _shaderFilterService.updateFilterVisuals(
          opacity: _alpha,
          brightness: _brightness,
        );
        _rememberCurrentBaseFilter();
        _scheduleTrayMenuRefresh();
      },
      onBaseColorChanged: (c) {
        setState(() => _baseColor = c);
        _persistBasicFilterNow();
        if (_shaderFilterService.mode != FilterApplyMode.none) {
          _shaderFilterService.stopFilter();
        } else if (_shaderFilterService.filterImageNotifier.value != null) {
          _shaderFilterService.filterImageNotifier.value = null;
        }
        _rememberCurrentBaseFilter();
        _scheduleTrayMenuRefresh();
      },
      onClose: _togglePanel,
      onFontFamilyChanged: widget.onFontFamilyChanged,
    );
  }
}

class ShaderPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final BaseShaderPaintState state;

  ShaderPainter({required this.shader, required this.state});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..shader = shader;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant ShaderPainter oldDelegate) =>
      !identical(oldDelegate.shader, shader) ||
      state.shouldRepaint(oldDelegate.state);
}
