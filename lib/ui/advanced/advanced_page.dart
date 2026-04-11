import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:window_manager/window_manager.dart';
import '../../models/advanced_config.dart';
import '../../models/filter_preset.dart';
import '../../services/settings_service.dart';
import '../../services/win32_helpers.dart';

/// 高级页面 — 专注模式、聚光灯、自动化规则、配置管理
class AdvancedPage extends StatefulWidget {
  final SettingsService settingsService;
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
  // 配置导入回调
  final void Function(AppConfig config)? onConfigImported;

  const AdvancedPage({
    super.key,
    required this.settingsService,
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
  });

  @override
  State<AdvancedPage> createState() => _AdvancedPageState();
}

class _AdvancedPageState extends State<AdvancedPage> {
  late FocusModeConfig _focus;
  late SpotlightConfig _spotlight;
  late RegionMaskConfig _regionMask;
  late List<AutomationRule> _rules;
  late bool _automationEnabled;
  String? _currentForegroundProcess;

  @override
  void initState() {
    super.initState();
    _focus = widget.focusModeConfig;
    _spotlight = widget.spotlightConfig;
    _regionMask = widget.regionMaskConfig;
    _rules = List.from(widget.automationRules);
    _automationEnabled = widget.automationEnabled;
    _detectCurrentProcess();
  }

  @override
  void didUpdateWidget(covariant AdvancedPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _focus = widget.focusModeConfig;
    _spotlight = widget.spotlightConfig;
    _regionMask = widget.regionMaskConfig;
    _rules = List.from(widget.automationRules);
    _automationEnabled = widget.automationEnabled;
  }

  Future<void> _detectCurrentProcess() async {
    final name = getForegroundProcessName();
    if (mounted) setState(() => _currentForegroundProcess = name);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      children: [
        _buildFocusAndSpotlightSection(),
        const SizedBox(height: 20),
        _buildRegionMaskSection(),
        const SizedBox(height: 20),
        _buildAutomationSection(),
        const SizedBox(height: 20),
        _buildConfigSection(),
        const SizedBox(height: 24),
      ],
    );
  }

  // ═══════════════════════════════════════════════
  //  专注模式 & 聚光灯
  // ═══════════════════════════════════════════════

  Widget _buildFocusAndSpotlightSection() {
    return _sectionCard(
      title: '视觉增强',
      child: Column(
        children: [
          _buildFocusModeCard(),
          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFEEEFF2)),
          const SizedBox(height: 14),
          _buildSpotlightCard(),
        ],
      ),
    );
  }

  Widget _buildFocusModeCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.center_focus_strong_rounded, size: 20, color: Color(0xFF3B82F6)),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('专注模式', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1D26))),
                  SizedBox(height: 2),
                  Text('除活动窗口外，其余区域变暗', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                ],
              ),
            ),
            Switch(
              value: _focus.enabled,
              activeColor: const Color(0xFF3B82F6),
              onChanged: (v) {
                setState(() {
                  _focus.enabled = v;
                  // 互斥：开启专注模式时关闭聚光灯
                  if (v && _spotlight.enabled) {
                    _spotlight.enabled = false;
                    widget.onSpotlightChanged(_spotlight);
                  }
                });
                widget.onFocusModeChanged(_focus);
              },
            ),
          ],
        ),
        if (_focus.enabled) ...[
          const SizedBox(height: 14),
          _buildLabeledSlider(
            label: '暗度',
            value: _focus.dimOpacity,
            min: 0.1,
            max: 0.9,
            onChanged: (v) {
              setState(() => _focus.dimOpacity = v);
              widget.onFocusModeChanged(_focus);
            },
          ),
          const SizedBox(height: 8),
          _buildLabeledSlider(
            label: '圆角',
            value: _focus.borderRadius,
            min: 0,
            max: 32,
            onChanged: (v) {
              setState(() => _focus.borderRadius = v);
              widget.onFocusModeChanged(_focus);
            },
          ),
        ],
      ],
    );
  }

  Widget _buildSpotlightCard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.flashlight_on_rounded, size: 20, color: Color(0xFFF97316)),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('聚光灯', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1D26))),
                  SizedBox(height: 2),
                  Text('鼠标周围亮圈，其余区域变暗', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                ],
              ),
            ),
            Switch(
              value: _spotlight.enabled,
              activeColor: const Color(0xFFF97316),
              onChanged: (v) {
                setState(() {
                  _spotlight.enabled = v;
                  // 互斥：开启聚光灯时关闭专注模式
                  if (v && _focus.enabled) {
                    _focus.enabled = false;
                    widget.onFocusModeChanged(_focus);
                  }
                });
                widget.onSpotlightChanged(_spotlight);
              },
            ),
          ],
        ),
        if (_spotlight.enabled) ...[
          const SizedBox(height: 14),
          _buildLabeledSlider(
            label: '半径',
            value: _spotlight.radius,
            min: 50,
            max: 600,
            onChanged: (v) {
              setState(() => _spotlight.radius = v);
              widget.onSpotlightChanged(_spotlight);
            },
          ),
          const SizedBox(height: 8),
          _buildLabeledSlider(
            label: '暗度',
            value: _spotlight.dimOpacity,
            min: 0.1,
            max: 0.9,
            onChanged: (v) {
              setState(() => _spotlight.dimOpacity = v);
              widget.onSpotlightChanged(_spotlight);
            },
          ),
          const SizedBox(height: 8),
          _buildLabeledSlider(
            label: '柔边',
            value: _spotlight.softEdge,
            min: 0,
            max: 150,
            onChanged: (v) {
              setState(() => _spotlight.softEdge = v);
              widget.onSpotlightChanged(_spotlight);
            },
          ),
        ],
      ],
    );
  }

  // ═══════════════════════════════════════════════
  //  区域遮罩
  // ═══════════════════════════════════════════════

  Widget _buildRegionMaskSection() {
    return _sectionCard(
      title: '区域遮罩',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 主开关
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.crop_free_rounded, size: 20, color: Color(0xFF10B981)),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('区域遮罩', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1D26))),
                    SizedBox(height: 2),
                    Text('滤镜仅在指定区域内生效', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                  ],
                ),
              ),
              Switch(
                value: _regionMask.enabled,
                activeColor: const Color(0xFF10B981),
                onChanged: (v) {
                  setState(() => _regionMask.enabled = v);
                  widget.onRegionMaskChanged(_regionMask);
                },
              ),
            ],
          ),
          if (_regionMask.enabled) ...[
            const SizedBox(height: 14),
            // 反转模式
            Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: _regionMask.inverted,
                    activeColor: const Color(0xFF10B981),
                    onChanged: (v) {
                      setState(() => _regionMask.inverted = v ?? false);
                      widget.onRegionMaskChanged(_regionMask);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                const Text('反转模式', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF4B5563))),
                const SizedBox(width: 8),
                const Text('(滤镜在区域外生效)', style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
              ],
            ),
            const SizedBox(height: 14),
            // 区域列表
            if (_regionMask.regions.isNotEmpty) ...[
              ...List.generate(_regionMask.regions.length, (i) => _buildRegionRow(i)),
              const SizedBox(height: 10),
            ],
            // 快捷区域按钮
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _quickRegionBtn('左半屏', Icons.vertical_split_outlined, () => _addQuickRegion(_leftHalf)),
                _quickRegionBtn('右半屏', Icons.vertical_split_outlined, () => _addQuickRegion(_rightHalf)),
                _quickRegionBtn('上半屏', Icons.horizontal_split_outlined, () => _addQuickRegion(_topHalf)),
                _quickRegionBtn('下半屏', Icons.horizontal_split_outlined, () => _addQuickRegion(_bottomHalf)),
                _quickRegionBtn('前台窗口', Icons.picture_in_picture_alt, _captureWindowRegion),
              ],
            ),
            const SizedBox(height: 10),
            // 自定义绘制按钮
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: widget.onStartDrawingRegion,
                icon: const Icon(Icons.draw_rounded, size: 16),
                label: const Text('+ 绘制自定义区域'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF10B981),
                  side: const BorderSide(color: Color(0xFF10B981)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRegionRow(int index) {
    final region = _regionMask.regions[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: Checkbox(
              value: region.enabled,
              activeColor: const Color(0xFF10B981),
              onChanged: (v) {
                setState(() => region.enabled = v ?? true);
                widget.onRegionMaskChanged(_regionMask);
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () => _renameRegion(index),
              child: Text(region.name,
                  style: TextStyle(
                    fontSize: 13,
                    color: region.enabled ? const Color(0xFF1A1D26) : const Color(0xFF9CA3AF),
                  )),
            ),
          ),
          Text('${region.points.length} 点', style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              setState(() => _regionMask.regions.removeAt(index));
              widget.onRegionMaskChanged(_regionMask);
            },
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close_rounded, size: 16, color: Color(0xFF9CA3AF)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _quickRegionBtn(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFFBBF7D0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: const Color(0xFF10B981)),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF059669))),
          ],
        ),
      ),
    );
  }

  List<Offset> _leftHalf(Size s) => [Offset.zero, Offset(s.width / 2, 0), Offset(s.width / 2, s.height), Offset(0, s.height)];
  List<Offset> _rightHalf(Size s) => [Offset(s.width / 2, 0), Offset(s.width, 0), Offset(s.width, s.height), Offset(s.width / 2, s.height)];
  List<Offset> _topHalf(Size s) => [Offset.zero, Offset(s.width, 0), Offset(s.width, s.height / 2), Offset(0, s.height / 2)];
  List<Offset> _bottomHalf(Size s) => [Offset(0, s.height / 2), Offset(s.width, s.height / 2), Offset(s.width, s.height), Offset(0, s.height)];

  void _addQuickRegion(List<Offset> Function(Size) pointsBuilder) {
    final screenSize = MediaQuery.of(context).size;
    final points = pointsBuilder(screenSize);
    final region = MaskRegion(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: '区域 ${_regionMask.regions.length + 1}',
      points: points,
    );
    setState(() => _regionMask.regions.add(region));
    widget.onRegionMaskChanged(_regionMask);
  }

  void _captureWindowRegion() {
    final rect = getForegroundWindowRect();
    if (rect == null) return;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    // 将物理坐标转为逻辑坐标
    final l = rect.left / dpr;
    final t = rect.top / dpr;
    final r = rect.right / dpr;
    final b = rect.bottom / dpr;
    final points = [Offset(l, t), Offset(r, t), Offset(r, b), Offset(l, b)];
    final region = MaskRegion(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: '前台窗口',
      points: points,
    );
    setState(() => _regionMask.regions.add(region));
    widget.onRegionMaskChanged(_regionMask);
  }

  void _renameRegion(int index) {
    final controller = TextEditingController(text: _regionMask.regions[index].name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名区域'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (newName.isNotEmpty) {
                setState(() => _regionMask.regions[index].name = newName);
                widget.onRegionMaskChanged(_regionMask);
              }
              Navigator.pop(ctx);
            },
            child: const Text('确认'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════
  //  自动化规则
  // ═══════════════════════════════════════════════

  Widget _buildAutomationSection() {
    return _sectionCard(
      title: '自动化规则',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.auto_awesome_rounded, size: 20, color: Color(0xFF22C55E)),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('进程绑定预设', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1D26))),
                    SizedBox(height: 2),
                    Text('当指定程序在前台时自动切换滤镜', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                  ],
                ),
              ),
              Switch(
                value: _automationEnabled,
                activeColor: const Color(0xFF22C55E),
                onChanged: (v) {
                  setState(() => _automationEnabled = v);
                  widget.onAutomationEnabledChanged(v);
                },
              ),
            ],
          ),
          if (_currentForegroundProcess != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.terminal_rounded, size: 14, color: Color(0xFF6B7280)),
                  const SizedBox(width: 6),
                  Text(
                    '当前前台: $_currentForegroundProcess',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280), fontFamily: 'Consolas'),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: _detectCurrentProcess,
                    child: const Icon(Icons.refresh, size: 14, color: Color(0xFF9CA3AF)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          // 规则列表
          for (int i = 0; i < _rules.length; i++) ...[
            _buildRuleRow(i),
            if (i < _rules.length - 1) const SizedBox(height: 8),
          ],
          const SizedBox(height: 12),
          // 添加规则按钮
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF3B82F6),
                side: const BorderSide(color: Color(0xFFD1D5DB)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('添加规则', style: TextStyle(fontSize: 13)),
              onPressed: _addRule,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRuleRow(int index) {
    final rule = _rules[index];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: rule.enabled ? const Color(0xFFF0FDF4) : const Color(0xFFFAFAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: rule.enabled ? const Color(0xFF86EFAC) : const Color(0xFFE5E7EB),
        ),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              setState(() => rule.enabled = !rule.enabled);
              widget.onAutomationRulesChanged(_rules);
            },
            child: Icon(
              rule.enabled ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 20,
              color: rule.enabled ? const Color(0xFF22C55E) : const Color(0xFF9CA3AF),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              rule.processName,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, fontFamily: 'Consolas', color: Color(0xFF1A1D26)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Icon(Icons.arrow_forward_rounded, size: 16, color: Color(0xFF9CA3AF)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              rule.presetName,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF3B82F6)),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              setState(() => _rules.removeAt(index));
              widget.onAutomationRulesChanged(_rules);
            },
            child: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF9CA3AF)),
          ),
        ],
      ),
    );
  }

  void _addRule() {
    final processCtrl = TextEditingController(text: _currentForegroundProcess ?? '');
    String selectedPreset = kBasicFilterPresets.first.name;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (_, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('添加自动化规则', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('进程名称', style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                  const SizedBox(height: 6),
                  TextField(
                    controller: processCtrl,
                    decoration: InputDecoration(
                      hintText: '例如: chrome.exe',
                      hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    style: const TextStyle(fontSize: 13, fontFamily: 'Consolas'),
                  ),
                  const SizedBox(height: 16),
                  const Text('切换到预设', style: TextStyle(fontSize: 13, color: Color(0xFF6B7280))),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: selectedPreset,
                    isExpanded: true,
                    decoration: InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: kBasicFilterPresets.map((p) => DropdownMenuItem(
                      value: p.name,
                      child: Text(p.name, style: const TextStyle(fontSize: 13)),
                    )).toList(),
                    onChanged: (v) {
                      if (v != null) setDialogState(() => selectedPreset = v);
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消', style: TextStyle(color: Color(0xFF9CA3AF))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () {
                  final name = processCtrl.text.trim();
                  if (name.isNotEmpty) {
                    setState(() {
                      _rules.add(AutomationRule(processName: name, presetName: selectedPreset));
                    });
                    widget.onAutomationRulesChanged(_rules);
                  }
                  Navigator.of(ctx).pop();
                },
                child: const Text('添加'),
              ),
            ],
          );
        });
      },
    );
  }

  // ═══════════════════════════════════════════════
  //  配置导入导出
  // ═══════════════════════════════════════════════

  Widget _buildConfigSection() {
    return _sectionCard(
      title: '配置管理',
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F3FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.import_export_rounded, size: 20, color: Color(0xFF7C3AED)),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('配置导入导出', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1D26))),
                    SizedBox(height: 2),
                    Text('导出或导入滤镜配置，跨设备同步', style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF7C3AED),
                    side: const BorderSide(color: Color(0xFF7C3AED)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.file_upload_outlined, size: 18),
                  label: const Text('导出配置', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  onPressed: _exportConfig,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF3B82F6),
                    side: const BorderSide(color: Color(0xFF3B82F6)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  icon: const Icon(Icons.file_download_outlined, size: 18),
                  label: const Text('导入配置', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  onPressed: _importConfig,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _exportConfig() async {
    await windowManager.setAlwaysOnTop(false);
    try {
      final config = AppConfig(
        brightness: widget.settingsService.getBrightness(),
        alpha: widget.settingsService.getAlpha(),
        baseColor: widget.settingsService.getBaseColor(),
        activePreset: widget.settingsService.getActivePreset(),
        recentColors: widget.settingsService.getRecentColors(),
        fontFamily: widget.settingsService.getFontFamily(),
        startupEnabled: widget.settingsService.getStartupEnabled(),
        themeMode: widget.settingsService.getThemeMode(),
        focusMode: _focus,
        spotlight: _spotlight,
        automationRules: _rules,
      );

      final jsonStr = const JsonEncoder.withIndent('  ').convert(config.toJson());
      final fileName = 'screenfilter_config_${DateTime.now().millisecondsSinceEpoch}.json';

      final location = await getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: [
          const XTypeGroup(label: '配置文件', extensions: ['json']),
        ],
      );

      if (location != null) {
        await File(location.path).writeAsString(jsonStr);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('配置已导出'), duration: Duration(seconds: 2)),
          );
        }
      }
    } finally {
      await windowManager.setAlwaysOnTop(true);
    }
  }

  Future<void> _importConfig() async {
    await windowManager.setAlwaysOnTop(false);
    try {
      const typeGroup = XTypeGroup(label: '配置文件', extensions: ['json']);
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null) return;

      final content = await File(file.path).readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      final config = AppConfig.fromJson(json);

      // Apply config
      await widget.settingsService.saveAll(
        brightness: config.brightness,
        alpha: config.alpha,
        baseColor: config.baseColor,
        activePreset: config.activePreset,
        recentColors: config.recentColors,
      );
      await widget.settingsService.setFontFamily(config.fontFamily);
      await widget.settingsService.setStartupEnabled(config.startupEnabled);
      await widget.settingsService.setThemeMode(config.themeMode);

      // Update local state
      setState(() {
        _focus = config.focusMode;
        _spotlight = config.spotlight;
        _rules = config.automationRules;
      });
      widget.onFocusModeChanged(_focus);
      widget.onSpotlightChanged(_spotlight);
      widget.onAutomationRulesChanged(_rules);

      // Save advanced settings
      await widget.settingsService.setFocusModeConfig(_focus);
      await widget.settingsService.setSpotlightConfig(_spotlight);
      await widget.settingsService.setAutomationRules(_rules);

      widget.onConfigImported?.call(config);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('配置已导入'), duration: Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e'), duration: const Duration(seconds: 3)),
        );
      }
    } finally {
      await windowManager.setAlwaysOnTop(true);
    }
  }

  // ═══════════════════════════════════════════════
  //  通用组件
  // ═══════════════════════════════════════════════

  Widget _sectionCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEEFF2)),
        boxShadow: const [
          BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2)),
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

  Widget _buildLabeledSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 36,
          child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
        ),
        Expanded(
          child: SliderTheme(
            data: const SliderThemeData(trackHeight: 3),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF3B82F6), fontFamily: 'Consolas'),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
