import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hsvcolor_picker/flutter_hsvcolor_picker.dart'
    as hsv_lib;
import 'package:file_selector/file_selector.dart';
import 'package:window_manager/window_manager.dart';
import 'color_picker/color_picker_panel.dart';
import 'widgets/screen_position_picker.dart';
import '../models/filter_preset.dart';
import '../models/overlay_component.dart';
import '../models/screen_effect.dart';
import '../models/advanced_config.dart';
import 'sandbox/shader_sandbox_page.dart';
import 'advanced/advanced_page.dart';
import '../services/settings_service.dart';
import '../services/shader_filter_service.dart';

class ConsolePanel extends StatefulWidget {
  final double brightness;
  final double alpha;
  final Color baseColor;
  final SettingsService settingsService;

  // 顶层组件
  final OverlayComponent clockComponent;
  final OverlayComponent sloganComponent;
  final OverlayComponent watermarkComponent;
  final ValueChanged<OverlayComponent> onOverlayChanged;

  // 沙盒滤镜
  final ShaderFilterService? shaderFilterService;

  // 高级功能
  final FocusModeConfig focusModeConfig;
  final SpotlightConfig spotlightConfig;
  final List<AutomationRule> automationRules;
  final bool automationEnabled;
  final ValueChanged<FocusModeConfig> onFocusModeChanged;
  final ValueChanged<SpotlightConfig> onSpotlightChanged;
  final RegionMaskConfig regionMaskConfig;
  final ValueChanged<RegionMaskConfig> onRegionMaskChanged;
  final VoidCallback onStartDrawingRegion;
  final ValueChanged<List<AutomationRule>> onAutomationRulesChanged;
  final ValueChanged<bool> onAutomationEnabledChanged;
  final void Function(AppConfig config)? onConfigImported;

  final Function(double) onBrightnessChanged;
  final Function(double) onAlphaChanged;
  final Function(Color) onBaseColorChanged;
  final VoidCallback onClose;
  final Function(String)? onFontFamilyChanged;

  const ConsolePanel({
    super.key,
    required this.brightness,
    required this.alpha,
    required this.baseColor,
    required this.settingsService,
    required this.clockComponent,
    required this.sloganComponent,
    required this.watermarkComponent,
    required this.onOverlayChanged,
    this.shaderFilterService,
    required this.focusModeConfig,
    required this.spotlightConfig,
    required this.automationRules,
    required this.automationEnabled,
    required this.onFocusModeChanged,
    required this.onSpotlightChanged,
    required this.regionMaskConfig,
    required this.onRegionMaskChanged,
    required this.onStartDrawingRegion,
    required this.onAutomationRulesChanged,
    required this.onAutomationEnabledChanged,
    this.onConfigImported,
    required this.onBrightnessChanged,
    required this.onAlphaChanged,
    required this.onBaseColorChanged,
    required this.onClose,
    this.onFontFamilyChanged,
  });

  @override
  State<ConsolePanel> createState() => _ConsolePanelState();
}

class _ConsolePanelState extends State<ConsolePanel> {
  int _selectedIndex = 0;

  final List<String> _menus = ['主页', '滤镜', '高级', '沙盒', '常规', '关于'];
  final List<IconData> _menuIcons = [
    Icons.home_outlined,
    Icons.tune_outlined,
    Icons.dashboard_customize_outlined,
    Icons.code_outlined,
    Icons.settings_outlined,
    Icons.info_outline
  ];

  String? _activePresetName;
  bool _sandboxActive = false;

  // 常规设置状态
  bool _startupEnabled = false;
  bool _startupLoading = true;
  late String _selectedFont;

  // 屏幕特效状态
  String? _activeEffectName;
  bool _effectLoading = false;

  late List<Color> _recentColors;

  /// 系统字体列表（异步加载）
  List<String> _systemFonts = _defaultFonts;

  static const List<String> _defaultFonts = [
    'Microsoft YaHei',
    'SimHei',
    'SimSun',
    'KaiTi',
    'FangSong',
    'Consolas',
    'Arial',
    'Times New Roman',
  ];

  @override
  void initState() {
    super.initState();
    _recentColors = widget.settingsService.getRecentColors();
    _activePresetName = widget.settingsService.getActivePreset();
    _sandboxActive = widget.shaderFilterService?.mode != FilterApplyMode.none;
    if (_sandboxActive) _activePresetName = null;
    widget.shaderFilterService?.modeNotifier.addListener(_onSandboxModeChanged);
    _loadSystemFonts();
    _selectedFont = widget.settingsService.getFontFamily();
    _detectStartupEnabled();
  }

  @override
  void dispose() {
    widget.shaderFilterService?.modeNotifier.removeListener(_onSandboxModeChanged);
    super.dispose();
  }

  void _onSandboxModeChanged() {
    final active = widget.shaderFilterService?.mode != FilterApplyMode.none;
    if (active) _clearActivePreset();
    if (!active) {
      // Filter stopped externally (sandbox page); clear effect highlight
      setState(() {
        _sandboxActive = false;
        _activeEffectName = null;
      });
    } else {
      setState(() => _sandboxActive = true);
    }
  }

  Future<void> _applyScreenEffect(ScreenEffect effect) async {
    final svc = widget.shaderFilterService;
    if (svc == null) return;
    if (svc.mode != FilterApplyMode.none) svc.stopFilter();
    setState(() {
      _effectLoading = true;
      _activeEffectName = null;
    });
    final result = svc.compileShader(effect.hlslCode);
    if (!result.success || !mounted) {
      if (mounted) setState(() => _effectLoading = false);
      return;
    }
    _clearActivePreset();
    final screenSize = MediaQuery.of(context).size;
    svc.applyFilter(FilterApplyMode.dynamic, screenSize, svc.accentColor);
    setState(() {
      _effectLoading = false;
      _activeEffectName = effect.name;
      _sandboxActive = true;
    });
  }

  void _stopScreenEffect() {
    widget.shaderFilterService?.stopFilter();
    setState(() {
      _activeEffectName = null;
      _sandboxActive = false;
    });
  }

  Future<void> _loadSystemFonts() async {
    try {
      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-Command',
         r"Add-Type -AssemblyName System.Drawing; "
         r"(New-Object System.Drawing.Text.InstalledFontCollection).Families | "
         r"ForEach-Object { $_.Name }"],
      );
      if (result.exitCode == 0) {
        final fonts = (result.stdout as String)
            .split('\n')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList()
          ..sort();
        if (fonts.isNotEmpty && mounted) {
          setState(() => _systemFonts = fonts);
        }
      }
    } catch (_) {
      // 回退到默认字体列表
    }
  }

  Future<void> _detectStartupEnabled() async {
    try {
      final result = await Process.run('powershell', [
        '-NoProfile', '-Command',
        r'$val = (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" '
        r'-Name "ScreenFilter" -ErrorAction SilentlyContinue)."ScreenFilter"; '
        r'if ($val) { Write-Output "1" } else { Write-Output "0" }'
      ]);
      if (mounted) {
        final enabled = (result.stdout as String).trim() == '1';
        setState(() {
          _startupEnabled = enabled;
          _startupLoading = false;
        });
        widget.settingsService.setStartupEnabled(enabled);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _startupEnabled = widget.settingsService.getStartupEnabled();
          _startupLoading = false;
        });
      }
    }
  }

  Future<void> _toggleStartup(bool enabled) async {
    setState(() => _startupEnabled = enabled);
    widget.settingsService.setStartupEnabled(enabled);
    try {
      if (enabled) {
        final exePath = Platform.resolvedExecutable;
        await Process.run('powershell', [
          '-NoProfile', '-Command',
          'Set-ItemProperty -Path "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run" '
          '-Name "ScreenFilter" -Value \'$exePath\''
        ]);
      } else {
        await Process.run('powershell', [
          '-NoProfile', '-Command',
          'Remove-ItemProperty -Path "HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Run" '
          '-Name "ScreenFilter" -ErrorAction SilentlyContinue'
        ]);
      }
    } catch (_) {
      // 如果操作失败，恢复原状态
      if (mounted) setState(() => _startupEnabled = !enabled);
    }
  }

  Future<void> _launchUrl(String url) async {
    await Process.run('cmd', ['/c', 'start', '', url]);
  }

  /// 用户做了自定义调节时，取消预设高亮
  void _clearActivePreset() {
    if (_activePresetName != null) {
      setState(() {
        _activePresetName = null;
        widget.settingsService.setActivePreset(null);
      });
    }
  }

  final List<Color> _presetColors = [
    Colors.amber, Colors.orange, Colors.deepOrange, Colors.red, Colors.pink,
    Colors.purple, Colors.deepPurple, Colors.indigo, Colors.blue, Colors.lightBlue,
    Colors.cyan, Colors.teal, Colors.green, Colors.lightGreen, Colors.lime,
    Colors.brown, Colors.blueGrey, Colors.black
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 720,
      height: 560,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 40,
            offset: Offset(0, 8),
          ),
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        children: [
          _buildSideBar(),
          Expanded(
            child: Column(
              children: [
                _buildHeader(),
                Expanded(
                  child: _buildContentArea(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSideBar() {
    return Container(
      width: 72,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: const BoxDecoration(
        color: Color(0xFF1E2030),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(18),
          bottomLeft: Radius.circular(18),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(2),
              child: Image.asset(
                'assets/screenfilter_logo.png',
                width: 36,
                height: 36,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.broken_image, size: 36, color: Colors.grey),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _menus.length,
              itemBuilder: (context, index) {
                final isSelected = _selectedIndex == index;
                return Tooltip(
                  message: _menus[index],
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedIndex = index;
                      });
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0x1FFFFFFF) : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isSelected ? _getSolidIcon(_menuIcons[index]) : _menuIcons[index],
                        size: 22,
                        color: isSelected ? Colors.white : const Color(0xFF8B92A5),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  IconData _getSolidIcon(IconData outlineIcon) {
    if (outlineIcon == Icons.home_outlined) return Icons.home;
    if (outlineIcon == Icons.tune_outlined) return Icons.tune;
    if (outlineIcon == Icons.dashboard_customize_outlined) return Icons.dashboard_customize;
    if (outlineIcon == Icons.code_outlined) return Icons.code;
    if (outlineIcon == Icons.settings_outlined) return Icons.settings;
    if (outlineIcon == Icons.info_outline) return Icons.info;
    return outlineIcon;
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF0F1F3), width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _menus[_selectedIndex],
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF1A1D26), letterSpacing: 0.3),
          ),
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: widget.onClose,
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.close_rounded, color: Color(0xFF9CA3AF), size: 20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentArea() {
    switch (_selectedIndex) {
      case 0:
        return _buildHomePage();
      case 1:
        return _buildFilterPage();
      case 2:
        return AdvancedPage(
          settingsService: widget.settingsService,
          focusModeConfig: widget.focusModeConfig,
          spotlightConfig: widget.spotlightConfig,
          regionMaskConfig: widget.regionMaskConfig,
          automationRules: widget.automationRules,
          automationEnabled: widget.automationEnabled,
          onFocusModeChanged: widget.onFocusModeChanged,
          onSpotlightChanged: widget.onSpotlightChanged,
          onRegionMaskChanged: widget.onRegionMaskChanged,
          onStartDrawingRegion: widget.onStartDrawingRegion,
          onAutomationRulesChanged: widget.onAutomationRulesChanged,
          onAutomationEnabledChanged: widget.onAutomationEnabledChanged,
          onConfigImported: widget.onConfigImported,
        );
      case 3:
        return widget.shaderFilterService != null
            ? ShaderSandboxPage(service: widget.shaderFilterService!)
            : const Center(child: Text('滤镜服务未就绪', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14)));
      case 4:
        return _buildGeneralPage();
      case 5:
        return _buildAboutPage();
      default:
        return const SizedBox();
    }
  }

  Widget _buildHomePage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            'assets/screenfilter_logo.png',
            width: 140,
            height: 140,
            errorBuilder: (context, error, stackTrace) =>
                const Icon(Icons.broken_image, size: 140, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          const Text(
            'ScreenFilter',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1D26),
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '专业屏幕滤镜 · 跨平台',
            style: TextStyle(fontSize: 13, color: Color(0xFF9CA3AF), letterSpacing: 0.5),
          ),
          const SizedBox(height: 48),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              '快捷滤镜',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6B7280)),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildHomeColorBlock(Colors.transparent, '清除', 0.0),
              const SizedBox(width: 28),
              _buildHomeColorBlock(const Color(0x33FFB300), '护眼', 0.15),
              const SizedBox(width: 28),
              _buildHomeColorBlock(const Color(0x80000000), '夜间', 0.4),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildHomeColorBlock(Color color, String label, double defaultAlpha) {
    return GestureDetector(
      onTap: () {
        // Find matching preset by name so the basic-filter page highlights it.
        final match = kBasicFilterPresets.where((p) => p.name == label).firstOrNull;
        if (match != null) {
          widget.onBaseColorChanged(match.baseColor);
          widget.onAlphaChanged(match.alpha);
          widget.onBrightnessChanged(match.brightness);
          setState(() {
            _activePresetName = label;
            widget.settingsService.setActivePreset(_activePresetName);
          });
        } else {
          _clearActivePreset();
          widget.onBaseColorChanged(color);
          widget.onAlphaChanged(defaultAlpha);
        }
      },
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFFE5E7EB), width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0D000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                )
              ]
            ),
            child: color == Colors.transparent
                ? const Icon(Icons.block_rounded, color: Color(0xFFBFC5CD), size: 24)
                : null,
          ),
          const SizedBox(height: 10),
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF4B5563)))
        ],
      ),
    );
  }

  Widget _buildFilterPage() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      children: [
        _buildSectionCard(
          title: '基础调节',
          child: Column(
            children: [
              _buildSlider('亮度 (Brightness)', widget.brightness, -1.0, 1.0, (v) {
                _clearActivePreset();
                widget.onBrightnessChanged(v);
              }, colors: const [Color(0xFF000000), Color(0xFFFFFFFF)]),
              const SizedBox(height: 16),
              _buildSlider('透明度 (Alpha)', widget.alpha, 0.0, 1.0, (v) {
                _clearActivePreset();
                widget.onAlphaChanged(v);
              }, colors: const [Color(0x00000000), Color(0xFF000000)]),
            ],
          ),
        ),
        
        const SizedBox(height: 24),
        
        const Text('主题色', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF1A1D26))),
        const SizedBox(height: 12),
        _buildWinStyleThemePanel(),
        const SizedBox(height: 24),

        const Text('预设中心', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: Color(0xFF1A1D26))),
        const SizedBox(height: 12),
        _buildPresetCenter(),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSectionCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEEFF2)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF1A1D26))),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildWinStyleThemePanel() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEEFF2)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('最近使用的颜色', style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _recentColors.map((c) => _buildWinStyleColorBlock(c)).toList(),
                ),
                const SizedBox(height: 24),
                const Text('Windows 颜色 (纯色滤镜)', style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _presetColors.map((c) => _buildWinStyleColorBlock(c)).toList(),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.black12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF0F1F3),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(14),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('自定义颜色', style: TextStyle(fontSize: 13, color: Color(0xFF4B5563))),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  onPressed: _openColorPickerDialog,
                  child: const Text('查看颜色', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWinStyleColorBlock(Color color) {
    // ignore: deprecated_member_use
    bool isSelected = !_sandboxActive && color.value == widget.baseColor.value;
    return GestureDetector(
      onTap: () {
        _clearActivePreset();
        widget.onBaseColorChanged(color);
      },
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF3B82F6) : const Color(0xFFE5E7EB),
            width: isSelected ? 2.5 : 1,
          ),
          boxShadow: isSelected ? const [BoxShadow(color: Color(0x1A3B82F6), blurRadius: 6, offset: Offset(0, 2))] : null,
        ),
        child: isSelected
            ? Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(2.0),
                  child: Icon(
                    Icons.check,
                    size: 16,
                    color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                  ),
                ),
              )
            : (color == Colors.transparent 
                ? const Icon(Icons.block, color: Colors.black26, size: 20) 
                : null),
      ),
    );
  }

  void _openColorPickerDialog() {
    Color tempColor = widget.baseColor;
    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E2030),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 340,
                  child: ColorPickerPanel(
                    color: tempColor,
                    paletteHeight: 200,
                    onChanged: (color) {
                      setDialogState(() {
                        tempColor = color;
                      });
                    },
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('取消',
                      style: TextStyle(color: Color(0xFF8B92A5))),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                  onPressed: () {
                    _clearActivePreset();
                    widget.onBaseColorChanged(tempColor);
                    // 将颜色选择器中的透明度同步回写到基础调节
                    widget.onAlphaChanged(tempColor.a);
                    setState(() {
                      // ignore: deprecated_member_use
                      _recentColors
                          .removeWhere((c) => c.value == tempColor.value);
                      _recentColors.insert(0, tempColor);
                      if (_recentColors.length > 5) {
                        _recentColors.removeLast();
                      }
                      widget.settingsService.setRecentColors(_recentColors);
                    });
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('完成'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ═══════════════════════════════════════════
  //  预设中心 — 磁贴式布局
  // ═══════════════════════════════════════════
  Widget _buildPresetCenter() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEEFF2)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('基础滤镜', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF6B7280))),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.3,
            ),
            itemCount: kBasicFilterPresets.length,
            itemBuilder: (context, index) => _buildPresetTile(kBasicFilterPresets[index]),
          ),
          const SizedBox(height: 20),
          const Text('顶层组件', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF6B7280))),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildOverlayTile(
                icon: Icons.access_time,
                label: '时钟',
                enabled: widget.clockComponent.enabled,
                onToggle: () {
                  setState(() {
                    widget.clockComponent.enabled = !widget.clockComponent.enabled;
                  });
                  widget.onOverlayChanged(widget.clockComponent);
                },
                onSettings: () => _openClockSettings(),
              ),
              const SizedBox(width: 8),
              _buildOverlayTile(
                icon: Icons.text_fields,
                label: '标语',
                enabled: widget.sloganComponent.enabled,
                onToggle: () {
                  setState(() {
                    widget.sloganComponent.enabled = !widget.sloganComponent.enabled;
                  });
                  widget.onOverlayChanged(widget.sloganComponent);
                },
                onSettings: () => _openSloganSettings(),
              ),
              const SizedBox(width: 8),
              _buildOverlayTile(
                icon: Icons.image,
                label: '水印',
                enabled: widget.watermarkComponent.enabled,
                onToggle: () {
                  setState(() {
                    widget.watermarkComponent.enabled = !widget.watermarkComponent.enabled;
                  });
                  widget.onOverlayChanged(widget.watermarkComponent);
                },
                onSettings: () => _openWatermarkSettings(),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('屏幕特效', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF6B7280))),
              if (_effectLoading)
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (int i = 0; i < kScreenEffects.length; i++) ...[
                Expanded(child: _buildEffectTile(kScreenEffects[i])),
                if (i < kScreenEffects.length - 1) const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOverlayTile({
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onToggle,
    required VoidCallback onSettings,
  }) {
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: enabled ? const Color(0x143B82F6) : const Color(0xFFFAFAFB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: enabled ? const Color(0xFF3B82F6) : const Color(0xFFE5E7EB),
            width: enabled ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: onToggle,
                  child: Icon(icon, size: 22, color: enabled ? const Color(0xFF3B82F6) : const Color(0xFF6B7280)),
                ),
                const SizedBox(width: 10),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onSettings,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.settings, size: 20,
                        color: enabled ? const Color(0xFF3B82F6) : const Color(0xFF9CA3AF)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            GestureDetector(
              onTap: onToggle,
              child: Text(label, style: TextStyle(
                fontSize: 11,
                fontWeight: enabled ? FontWeight.w700 : FontWeight.w500,
                color: enabled ? const Color(0xFF3B82F6) : const Color(0xFF4B5563),
              )),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEffectTile(ScreenEffect effect) {
    final isActive = _activeEffectName == effect.name;
    return GestureDetector(
      onTap: _effectLoading
          ? null
          : () {
              if (isActive) {
                _stopScreenEffect();
              } else {
                _applyScreenEffect(effect);
              }
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: isActive ? effect.tileColor : const Color(0xFFFAFAFB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive ? effect.iconColor : const Color(0xFFE5E7EB),
            width: isActive ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(effect.icon, size: 20,
                color: isActive ? effect.iconColor : const Color(0xFF9CA3AF)),
            const SizedBox(height: 4),
            Text(
              effect.name,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? effect.iconColor : const Color(0xFF6B7280),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetTile(FilterPreset preset) {
    final isActive = !_sandboxActive && _activePresetName == preset.name;
    return GestureDetector(
      onTap: () {
        // Stop any running screen effect
        if (_activeEffectName != null) _stopScreenEffect();
        if (isActive) {
          // Second tap on active preset → clear filter.
          final clearPreset = kBasicFilterPresets.firstWhere((p) => p.name == '清除');
          widget.onBaseColorChanged(clearPreset.baseColor);
          widget.onAlphaChanged(clearPreset.alpha);
          widget.onBrightnessChanged(clearPreset.brightness);
          setState(() {
            _activePresetName = null;
            widget.settingsService.setActivePreset(null);
          });
        } else {
          widget.onBaseColorChanged(preset.baseColor);
          widget.onAlphaChanged(preset.alpha);
          widget.onBrightnessChanged(preset.brightness);
          setState(() {
            _activePresetName = preset.name;
            widget.settingsService.setActivePreset(_activePresetName);
          });
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isActive ? preset.tileColor : const Color(0xFFFAFAFB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive ? const Color(0xFF3B82F6) : const Color(0xFFE5E7EB),
            width: isActive ? 2 : 1,
          ),
          boxShadow: isActive
              ? const [
                  BoxShadow(
                    color: Color(0x1A3B82F6),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              preset.icon,
              size: 18,
              color: isActive ? const Color(0xFF3B82F6) : const Color(0xFF6B7280),
            ),
            const SizedBox(height: 4),
            Text(
              preset.name,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive ? const Color(0xFF3B82F6) : const Color(0xFF4B5563),
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlider(String label, double value, double min, double max, ValueChanged<double> onChanged, {List<Color>? colors}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Row(
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF4B5563))),
              const Spacer(),
              Text(
                value.toStringAsFixed(2),
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF3B82F6)),
              ),
            ],
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: hsv_lib.SliderPicker(
            value: ((value - min) / (max - min)).clamp(0.0, 1.0),
            min: 0.0,
            max: 1.0,
            onChanged: (ratio) => onChanged(ratio * (max - min) + min),
            colors: colors,
            height: 32,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[300]!, width: 0.5),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════
  //  顶层组件配置弹窗
  // ═══════════════════════════════════════════

  /// 通用颜色选择弹窗（使用 ColorPickerPanel）
  void _openOverlayColorPicker(Color currentColor, ValueChanged<Color> onConfirm) {
    Color tempColor = currentColor;
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (_, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF1E2030),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 340,
                child: ColorPickerPanel(
                  color: tempColor,
                  paletteHeight: 180,
                  onChanged: (c) => setDialogState(() => tempColor = c),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消', style: TextStyle(color: Color(0xFF8B92A5))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6), foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  onConfirm(tempColor);
                  Navigator.of(ctx).pop();
                },
                child: const Text('确定'),
              ),
            ],
          );
        });
      },
    );
  }

  /// 颜色选择行：色块预览 + "自定义" 按钮
  Widget _buildColorRow(String label, Color color, ValueChanged<Color> onColorChanged, void Function(VoidCallback) setDialogState) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        const Spacer(),
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.black26),
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: () {
            _openOverlayColorPicker(color, (c) {
              setDialogState(() => onColorChanged(c));
            });
          },
          child: const Text('自定义', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  // ── 常用字体列表已移至 _systemFonts 动态加载 ──

  /// 设置分组卡片（圆角矩形框）
  Widget _settingsGroup({required String title, required IconData icon, required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEFF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: const Color(0xFF3B82F6)),
              const SizedBox(width: 6),
              Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF3B82F6))),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  /// 带可编辑数值的滑条行
  Widget _buildEditableSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required bool isInt,
    required ValueChanged<double> onChanged,
  }) {
    final displayText = isInt ? '${value.round()}' : value.toStringAsFixed(2);
    return Row(
      children: [
        SizedBox(width: 42, child: Text(label, style: const TextStyle(fontSize: 13))),
        Expanded(
          child: Slider(
            value: value, min: min, max: max,
            onChanged: onChanged,
          ),
        ),
        GestureDetector(
          onTap: () {
            final ctrl = TextEditingController(text: displayText);
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                title: Text('输入$label', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                content: TextField(
                  controller: ctrl,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                  ],
                  decoration: InputDecoration(
                    hintText: '${min.toStringAsFixed(isInt ? 0 : 2)} - ${max.toStringAsFixed(isInt ? 0 : 2)}',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (v) {
                    final parsed = double.tryParse(v);
                    if (parsed != null) {
                      onChanged(parsed.clamp(min, max));
                    }
                    Navigator.pop(ctx);
                  },
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消', style: TextStyle(color: Color(0xFF9CA3AF)))),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      final parsed = double.tryParse(ctrl.text);
                      if (parsed != null) {
                        onChanged(parsed.clamp(min, max));
                      }
                      Navigator.pop(ctx);
                    },
                    child: const Text('确定'),
                  ),
                ],
              ),
            );
          },
          child: Container(
            width: 48,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Text(
              displayText,
              style: const TextStyle(fontSize: 12, color: Color(0xFF1A1D26), fontFamily: 'Consolas'),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  void _openClockSettings() {
    final comp = widget.clockComponent;
    var config = comp.clockConfig ?? const ClockConfig();
    var position = comp.position;
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('时钟设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 360,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _settingsGroup(
                      title: '显示样式',
                      icon: Icons.style,
                      children: [
                        Row(
                          children: [
                            const Text('样式', style: TextStyle(fontSize: 13)),
                            const Spacer(),
                            SegmentedButton<ClockStyle>(
                              segments: const [
                                ButtonSegment(value: ClockStyle.digital, label: Text('数字', style: TextStyle(fontSize: 12))),
                                ButtonSegment(value: ClockStyle.analog, label: Text('模拟', style: TextStyle(fontSize: 12))),
                              ],
                              selected: {config.style},
                              onSelectionChanged: (v) {
                                setDialogState(() => config = config.copyWith(style: v.first));
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text('字号', style: TextStyle(fontSize: 13)),
                            Expanded(
                              child: Slider(
                                value: config.fontSize, min: 16, max: 120,
                                onChanged: (v) => setDialogState(() => config = config.copyWith(fontSize: v)),
                              ),
                            ),
                            Text('${config.fontSize.round()}', style: const TextStyle(fontSize: 13)),
                          ],
                        ),
                        _buildColorRow('颜色', config.color, (c) {
                          config = config.copyWith(color: c);
                        }, setDialogState),
                      ],
                    ),
                    _settingsGroup(
                      title: '时间格式',
                      icon: Icons.access_time,
                      children: [
                        SwitchListTile(
                          dense: true, contentPadding: EdgeInsets.zero,
                          title: const Text('24 小时制', style: TextStyle(fontSize: 13)),
                          value: config.show24Hour,
                          onChanged: (v) => setDialogState(() => config = config.copyWith(show24Hour: v)),
                        ),
                        SwitchListTile(
                          dense: true, contentPadding: EdgeInsets.zero,
                          title: const Text('显示秒数', style: TextStyle(fontSize: 13)),
                          value: config.showSeconds,
                          onChanged: (v) => setDialogState(() => config = config.copyWith(showSeconds: v)),
                        ),
                      ],
                    ),
                    _settingsGroup(
                      title: '屏幕位置',
                      icon: Icons.pin_drop,
                      children: [
                        ScreenPositionPicker(
                          position: position,
                          label: '时钟',
                          componentSize: Size(config.fontSize * 5, config.fontSize * 1.5),
                          onPositionChanged: (pos) => setDialogState(() => position = pos),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消', style: TextStyle(color: Color(0xFF9CA3AF))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6), foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  setState(() {
                    comp.clockConfig = config;
                    comp.position = position;
                    comp.enabled = true;
                  });
                  widget.onOverlayChanged(comp);
                  Navigator.of(ctx).pop();
                },
                child: const Text('应用'),
              ),
            ],
          );
        });
      },
    );
  }

  void _openSloganSettings() {
    final comp = widget.sloganComponent;
    var config = comp.sloganConfig ?? const SloganConfig();
    var position = comp.position;
    final textController = TextEditingController(text: config.text);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('标语设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 360,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _settingsGroup(
                      title: '文本内容',
                      icon: Icons.edit,
                      children: [
                        TextField(
                          controller: textController,
                          decoration: const InputDecoration(
                            labelText: '标语文本',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (v) => setDialogState(() => config = config.copyWith(text: v)),
                        ),
                      ],
                    ),
                    _settingsGroup(
                      title: '字体样式',
                      icon: Icons.text_format,
                      children: [
                        Row(
                          children: [
                            const Text('字号', style: TextStyle(fontSize: 13)),
                            Expanded(
                              child: Slider(
                                value: config.fontSize, min: 12, max: 96,
                                onChanged: (v) => setDialogState(() => config = config.copyWith(fontSize: v)),
                              ),
                            ),
                            Text('${config.fontSize.round()}', style: const TextStyle(fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Text('字体', style: TextStyle(fontSize: 13)),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _systemFonts.contains(config.fontFamily) ? config.fontFamily : _systemFonts.first,
                                isExpanded: true,
                                menuMaxHeight: 300,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  border: OutlineInputBorder(),
                                ),
                                items: _systemFonts.map((f) => DropdownMenuItem(
                                  value: f,
                                  child: Text(f, style: TextStyle(fontSize: 13, fontFamily: f)),
                                )).toList(),
                                onChanged: (v) {
                                  if (v != null) setDialogState(() => config = config.copyWith(fontFamily: v));
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const Text('字重', style: TextStyle(fontSize: 13)),
                            const Spacer(),
                            SegmentedButton<FontWeight>(
                              segments: const [
                                ButtonSegment(value: FontWeight.w400, label: Text('常规', style: TextStyle(fontSize: 11))),
                                ButtonSegment(value: FontWeight.w700, label: Text('粗体', style: TextStyle(fontSize: 11))),
                                ButtonSegment(value: FontWeight.w900, label: Text('黑体', style: TextStyle(fontSize: 11))),
                              ],
                              selected: {config.fontWeight},
                              onSelectionChanged: (v) => setDialogState(() => config = config.copyWith(fontWeight: v.first)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _buildColorRow('颜色', config.color, (c) {
                          config = config.copyWith(color: c);
                        }, setDialogState),
                      ],
                    ),
                    _settingsGroup(
                      title: '效果预览',
                      icon: Icons.visibility,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A2A3A),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            config.text.isEmpty ? '预览' : config.text,
                            style: TextStyle(
                              fontSize: (config.fontSize * 0.4).clamp(12, 32),
                              fontWeight: config.fontWeight,
                              fontFamily: config.fontFamily,
                              color: config.color,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                    _settingsGroup(
                      title: '屏幕位置',
                      icon: Icons.pin_drop,
                      children: [
                        ScreenPositionPicker(
                          position: position,
                          label: '标语',
                          componentSize: Size(config.text.length * config.fontSize * 0.6, config.fontSize * 1.5),
                          onPositionChanged: (pos) => setDialogState(() => position = pos),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消', style: TextStyle(color: Color(0xFF9CA3AF))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6), foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  setState(() {
                    comp.sloganConfig = config;
                    comp.position = position;
                    comp.enabled = true;
                  });
                  widget.onOverlayChanged(comp);
                  Navigator.of(ctx).pop();
                },
                child: const Text('应用'),
              ),
            ],
          );
        });
      },
    );
  }

  void _openWatermarkSettings() {
    final comp = widget.watermarkComponent;
    var config = comp.watermarkConfig ?? const WatermarkConfig();
    var position = comp.position;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('水印设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 360,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _settingsGroup(
                      title: '图片选择',
                      icon: Icons.image,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                config.imagePath.isEmpty ? '未选择图片' : config.imagePath.split(RegExp(r'[/\\]')).last,
                                style: TextStyle(fontSize: 13, color: config.imagePath.isEmpty ? const Color(0xFF9CA3AF) : const Color(0xFF1A1D26)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFEEEFF2),
                                foregroundColor: const Color(0xFF4B5563),
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              ),
                              icon: const Icon(Icons.folder_open, size: 18),
                              label: const Text('浏览', style: TextStyle(fontSize: 13)),
                              onPressed: () async {
                                // 临时取消置顶，避免覆盖原生文件对话框
                                await windowManager.setAlwaysOnTop(false);
                                try {
                                  const typeGroup = XTypeGroup(
                                    label: '图片文件',
                                    extensions: ['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp'],
                                  );
                                  final file = await openFile(acceptedTypeGroups: [typeGroup]);
                                  if (file != null) {
                                    setDialogState(() {
                                      config = config.copyWith(imagePath: file.path);
                                    });
                                  }
                                } finally {
                                  await windowManager.setAlwaysOnTop(true);
                                }
                              },
                            ),
                          ],
                        ),
                        if (config.imagePath.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            key: ValueKey('preview_${config.imagePath}'),
                            height: 100,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A2A3A),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(7),
                              child: Opacity(
                                opacity: config.opacity,
                                child: Image.file(
                                  File(config.imagePath),
                                  key: ValueKey(config.imagePath),
                                  fit: BoxFit.contain,
                                  gaplessPlayback: true,
                                  errorBuilder: (_, __, ___) => const Center(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.broken_image, color: Colors.white38, size: 28),
                                        SizedBox(height: 4),
                                        Text('无法加载图片', style: TextStyle(color: Colors.white54, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    _settingsGroup(
                      title: '尺寸与透明度',
                      icon: Icons.aspect_ratio,
                      children: [
                        _buildEditableSliderRow(
                          label: '宽度',
                          value: config.width, min: 50, max: 800,
                          isInt: true,
                          onChanged: (v) => setDialogState(() => config = config.copyWith(width: v)),
                        ),
                        _buildEditableSliderRow(
                          label: '高度',
                          value: config.height, min: 50, max: 800,
                          isInt: true,
                          onChanged: (v) => setDialogState(() => config = config.copyWith(height: v)),
                        ),
                        _buildEditableSliderRow(
                          label: '透明度',
                          value: config.opacity, min: 0.05, max: 1.0,
                          isInt: false,
                          onChanged: (v) => setDialogState(() => config = config.copyWith(opacity: v)),
                        ),
                      ],
                    ),
                    _settingsGroup(
                      title: '屏幕位置',
                      icon: Icons.pin_drop,
                      children: [
                        ScreenPositionPicker(
                          position: position,
                          label: '水印',
                          componentSize: Size(config.width, config.height),
                          onPositionChanged: (pos) => setDialogState(() => position = pos),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消', style: TextStyle(color: Color(0xFF9CA3AF))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6), foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  setState(() {
                    comp.watermarkConfig = config;
                    comp.position = position;
                    comp.enabled = true;
                  });
                  widget.onOverlayChanged(comp);
                  Navigator.of(ctx).pop();
                },
                child: const Text('应用'),
              ),
            ],
          );
        });
      },
    );
  }

  Widget _buildGeneralPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── 系统 ───
          _buildSectionCard(
            title: '系统',
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.computer_rounded, size: 20, color: Color(0xFF3B82F6)),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('开机自启动', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1D26))),
                      SizedBox(height: 2),
                      Text('登录 Windows 时自动启动应用', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                    ],
                  ),
                ),
                _startupLoading
                    ? const SizedBox(width: 36, height: 20, child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))))
                    : Switch(
                        value: _startupEnabled,
                        activeThumbColor: const Color(0xFF3B82F6),
                        onChanged: _toggleStartup,
                      ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ─── 外观 ───
          _buildSectionCard(
            title: '外观',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 字体选择
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.font_download_outlined, size: 20, color: Color(0xFF22C55E)),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('界面字体', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1D26))),
                          Text('更改控制台文字字体', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<String>(
                      value: _systemFonts.contains(_selectedFont) ? _selectedFont : _systemFonts.first,
                      underline: const SizedBox(),
                      style: const TextStyle(fontSize: 13, color: Color(0xFF1A1D26)),
                      borderRadius: BorderRadius.circular(10),
                      items: _systemFonts.map((f) => DropdownMenuItem(value: f, child: Text(f, style: const TextStyle(fontSize: 13)))).toList(),
                      onChanged: (font) {
                        if (font == null) return;
                        setState(() => _selectedFont = font);
                        widget.onFontFamilyChanged?.call(font);
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 16),
                const Divider(color: Color(0xFFEEEFF2), height: 1),
                const SizedBox(height: 16),

                // 皮肤切换
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.palette_outlined, size: 20, color: Color(0xFFF97316)),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('界面皮肤', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1D26))),
                          Text('浅色 / 深色主题（即将推出）', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('即将推出', style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF), fontWeight: FontWeight.w500)),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ─── 语言 ───
          _buildSectionCard(
            title: '语言',
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F3FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.language_rounded, size: 20, color: Color(0xFF7C3AED)),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('界面语言', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1D26))),
                      Text('更改界面显示语言（即将支持更多语言）', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: const Text('简体中文', style: TextStyle(fontSize: 13, color: Color(0xFF4B5563), fontWeight: FontWeight.w500)),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildAboutPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── 应用信息 ───
          _buildSectionCard(
            title: '应用信息',
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2))],
                  ),
                  padding: const EdgeInsets.all(6),
                  child: Image.asset(
                    'assets/screenfilter_logo.png',
                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 44, color: Colors.grey),
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ScreenFilter', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1A1D26))),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF2FF),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('v4.0.0 Alpha', style: TextStyle(fontSize: 11, color: Color(0xFF3B82F6), fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 4),
                    const Text('构建于 Flutter + DirectX 11', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ─── 更新 ───
          _buildSectionCard(
            title: '更新中心',
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.system_update_alt_rounded, size: 20, color: Color(0xFF3B82F6)),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('检查更新', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1D26))),
                      Text('当前已是最新版本 (v4.0.0)', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                    ],
                  ),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF3B82F6),
                    side: const BorderSide(color: Color(0xFF3B82F6)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () {},
                  child: const Text('检查更新', style: TextStyle(fontSize: 13)),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ─── 链接 ───
          _buildSectionCard(
            title: '链接',
            child: Column(
              children: [
                _buildLinkRow(
                  icon: Icons.code_rounded,
                  iconBg: const Color(0xFF1A1D26),
                  iconColor: Colors.white,
                  label: 'GitHub 仓库',
                  subtitle: 'github.com/deceive777xv/ScreenFilter',
                  onTap: () => _launchUrl('https://github.com/deceive777xv/ScreenFilter'),
                ),
                const SizedBox(height: 12),
                const Divider(color: Color(0xFFEEEFF2), height: 1),
                const SizedBox(height: 12),
                _buildLinkRow(
                  icon: Icons.bug_report_outlined,
                  iconBg: const Color(0xFFFFF1F2),
                  iconColor: const Color(0xFFEF4444),
                  label: '反馈问题',
                  subtitle: '在 GitHub Issues 提交 Bug 或建议',
                  onTap: () => _launchUrl('https://github.com/deceive777xv/ScreenFilter/issues'),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ─── 操作 ───
          _buildSectionCard(
            title: '操作',
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFEF4444),
                  side: const BorderSide(color: Color(0xFFEF4444), width: 1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                icon: const Icon(Icons.exit_to_app_rounded, size: 18),
                label: const Text('完全退出程序', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                onPressed: () => exit(0),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // 版权信息
          const Center(
            child: Text(
              '© 2026 ScreenFilter. All rights reserved.',
              style: TextStyle(fontSize: 11, color: Color(0xFFD1D5DB)),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildLinkRow({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1D26))),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
              ],
            ),
          ),
          const Icon(Icons.open_in_new_rounded, size: 16, color: Color(0xFFD1D5DB)),
        ],
      ),
    );
  }
}



