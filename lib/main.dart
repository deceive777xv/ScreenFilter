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
import 'services/settings_service.dart';
import 'services/shader_filter_service.dart';
import 'services/win32_helpers.dart';

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

  // 沙盒自定义滤镜
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
  Timer? _automationTimer;
  String? _lastMatchedPreset;
  bool _isDrawingRegion = false;

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

    initSystemTray();
    _loadShader();

    // Init shader filter service
    _shaderFilterService = ShaderFilterService();
    _shaderFilterService.init();
    _shaderFilterService.modeNotifier.addListener(_onSandboxModeChanged);

    // Start automation if enabled
    if (_automationEnabled) _startAutomation();
  }

  void _onSandboxModeChanged() {
    // 沙盒/特效激活时，若当前 alpha 为 0（清除状态），自动提升到 1.0 以确保可见
    if (_shaderFilterService.mode != FilterApplyMode.none && _alpha == 0.0) {
      _alpha = 1.0;
      _settings.setAlpha(_alpha);
    }
    setState(() {});
  }

  @override
  void dispose() {
    _automationTimer?.cancel();
    _shaderFilterService.modeNotifier.removeListener(_onSandboxModeChanged);
    _shaderFilterService.dispose();
    _systemTray.destroy();
    super.dispose();
  }

  Future<void> _loadShader() async {
    try {
      ui.FragmentProgram program = await ui.FragmentProgram.fromAsset('shaders/filter.frag');
      setState(() {
        _shader = program.fragmentShader();
      });
    } catch (e) {
      debugPrint('Error loading shader: $e');
    }
  }

  Future<void> initSystemTray() async {
    String path = Platform.isWindows ? 'assets/screenfilter_icon.ico' : 'assets/screenfilter_icon.png';
    try {
      await _systemTray.initSystemTray(
        title: 'Filter',
        iconPath: path,
        toolTip: '滤镜 - 点击打开设置',
      );

      // 右键菜单
      final Menu menu = Menu();
      await menu.buildFrom([
        MenuItemLabel(label: '显示/隐藏面板', onClicked: (menuItem) => _togglePanel()),
        MenuSeparator(),
        MenuItemLabel(label: '退出', onClicked: (menuItem) {
          _shaderFilterService.dispose();
          _systemTray.destroy();
          exit(0);
        }),
      ]);
      await _systemTray.setContextMenu(menu);

      _systemTray.registerSystemTrayEventHandler((eventName) {
        if (eventName == kSystemTrayEventClick) {
          _togglePanel();
        } else if (eventName == kSystemTrayEventRightClick) {
          _systemTray.popUpContextMenu();
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
      setState(() => _isPanelOpen = true);
      await windowManager.setIgnoreMouseEvents(false);
    }
  }

  void _onOverlayChanged(OverlayComponent component) {
    setState(() {});
    _settings.setOverlayComponent(component);
  }

  // ── 高级功能回调 ──────────────────────────────────────────────

  void _onFocusModeChanged(FocusModeConfig config) {
    setState(() => _focusModeConfig = config);
    _settings.setFocusModeConfig(config);
  }

  void _onSpotlightChanged(SpotlightConfig config) {
    setState(() => _spotlightConfig = config);
    _settings.setSpotlightConfig(config);
  }

  void _onRegionMaskChanged(RegionMaskConfig config) {
    setState(() => _regionMaskConfig = config);
    _settings.setRegionMaskConfig(config);
  }

  void _startDrawingRegion() {
    setState(() {
      _isDrawingRegion = true;
      _isPanelOpen = false;
    });
    windowManager.setIgnoreMouseEvents(false);
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
    _settings.setRegionMaskConfig(_regionMaskConfig);
  }

  void _onDrawingCancel() {
    setState(() {
      _isDrawingRegion = false;
      _isPanelOpen = true;
    });
  }

  void _onAutomationRulesChanged(List<AutomationRule> rules) {
    setState(() => _automationRules = rules);
    _settings.setAutomationRules(rules);
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

  void _startAutomation() {
    _automationTimer?.cancel();
    _automationTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _checkAutomationRules();
    });
  }

  void _stopAutomation() {
    _automationTimer?.cancel();
    _automationTimer = null;
    _lastMatchedPreset = null;
  }

  void _checkAutomationRules() {
    if (!_automationEnabled || _automationRules.isEmpty) return;
    final processName = getForegroundProcessName();
    if (processName == null) return;

    final lowerProcess = processName.toLowerCase();
    for (final rule in _automationRules) {
      if (!rule.enabled) continue;
      if (lowerProcess == rule.processName.toLowerCase()) {
        if (_lastMatchedPreset != rule.presetName) {
          _lastMatchedPreset = rule.presetName;
          _applyPresetByName(rule.presetName);
        }
        return;
      }
    }
    // No rule matched — clear last match so it can re-trigger later
    _lastMatchedPreset = null;
  }

  void _applyPresetByName(String name) {
    final match = kBasicFilterPresets.where((p) => p.name == name).firstOrNull;
    if (match == null) return;
    setState(() {
      _baseColor = match.baseColor;
      _alpha = match.alpha;
      _brightness = match.brightness;
    });
    _settings.setBrightness(match.brightness);
    _settings.setAlpha(match.alpha);
    _settings.setBaseColor(match.baseColor);
    _settings.setActivePreset(name);
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
    });
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    _shaderFilterService.updateScreenSize(MediaQuery.of(context).size);
    _shaderFilterService.updateDevicePixelRatio(MediaQuery.of(context).devicePixelRatio);
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
                      if (image == null || _shaderFilterService.mode == FilterApplyMode.none) {
                        return const SizedBox();
                      }
                      Widget child = SizedBox.expand(
                        child: RawImage(image: image, fit: BoxFit.cover),
                      );
                      if (_brightness != 0) {
                        child = ColorFiltered(
                          colorFilter: ColorFilter.matrix(_makeBrightnessMatrix(_brightness)),
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
                      _settings.setOverlayComponent(_clockComponent);
                    },
                  ),
                  SloganOverlay(
                    component: _sloganComponent,
                    draggable: _isPanelOpen,
                    onPositionChanged: (pos) {
                      setState(() => _sloganComponent.position = pos);
                      _settings.setOverlayComponent(_sloganComponent);
                    },
                  ),
                  WatermarkOverlay(
                    component: _watermarkComponent,
                    draggable: _isPanelOpen,
                    onPositionChanged: (pos) {
                      setState(() => _watermarkComponent.position = pos);
                      _settings.setOverlayComponent(_watermarkComponent);
                    },
                  ),
                ],
              ),
            ),
          ),
          if (_isPanelOpen)
            Center(child: _buildPanel()),
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
      return [
        s, 0, 0, 0, 0,
        0, s, 0, 0, 0,
        0, 0, s, 0, 0,
        0, 0, 0, 1, 0,
      ];
    } else {
      final s = 1.0 - brightness * 0.95;
      final o = brightness * 0.95 * 255;
      return [
        s, 0, 0, 0, o,
        0, s, 0, 0, o,
        0, 0, s, 0, o,
        0, 0, 0, 1, 0,
      ];
    }
  }

  Widget _buildShaderFilter() {
    if (_shader == null) return const SizedBox();

    final sandboxActive = _shaderFilterService.mode != FilterApplyMode.none;
    // 当沙盒/特效激活时，GLSL层全透明无需渲染，直接跳过以避免干扰DX11叠加层
    if (sandboxActive) return const SizedBox();

    return Builder(builder: (context) {
      final size = MediaQuery.of(context).size;

      _shader!.setFloat(0, size.width);
      _shader!.setFloat(1, size.height);
      _shader!.setFloat(2, _brightness);
      _shader!.setFloat(3, _alpha);
      _shader!.setFloat(4, _baseColor.r);
      _shader!.setFloat(5, _baseColor.g);
      _shader!.setFloat(6, _baseColor.b);
      _shader!.setFloat(7, _baseColor.a);

      return CustomPaint(
        size: Size.infinite,
        painter: ShaderPainter(shader: _shader!),
      );
    });
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
      onFocusModeChanged: _onFocusModeChanged,
      onSpotlightChanged: _onSpotlightChanged,
      regionMaskConfig: _regionMaskConfig,
      onRegionMaskChanged: _onRegionMaskChanged,
      onStartDrawingRegion: _startDrawingRegion,
      onAutomationRulesChanged: _onAutomationRulesChanged,
      onAutomationEnabledChanged: _onAutomationEnabledChanged,
      onConfigImported: _onConfigImported,
      onBrightnessChanged: (v) {
        setState(() => _brightness = v);
        _settings.setBrightness(v);
      },
      onAlphaChanged: (v) {
        setState(() => _alpha = v);
        _settings.setAlpha(v);
      },
      onBaseColorChanged: (c) {
        setState(() => _baseColor = c);
        _settings.setBaseColor(c);
        if (_shaderFilterService.mode != FilterApplyMode.none) {
          _shaderFilterService.stopFilter();
        } else if (_shaderFilterService.filterImageNotifier.value != null) {
          _shaderFilterService.filterImageNotifier.value = null;
        }
      },
      onClose: _togglePanel,
      onFontFamilyChanged: widget.onFontFamilyChanged,
    );
  }
}

class ShaderPainter extends CustomPainter {
  final ui.FragmentShader shader;

  ShaderPainter({required this.shader});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..shader = shader;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
