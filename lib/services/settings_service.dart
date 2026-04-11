import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/overlay_component.dart';
import '../models/advanced_config.dart';

/// 应用设置持久化服务
class SettingsService {
  static const _keyBrightness = 'filter_brightness';
  static const _keyAlpha = 'filter_alpha';
  static const _keyBaseColorValue = 'filter_base_color';
  static const _keyActivePreset = 'filter_active_preset';
  static const _keyRecentColors = 'filter_recent_colors';
  static const _keyOverlayClock = 'overlay_clock';
  static const _keyOverlaySlogan = 'overlay_slogan';
  static const _keyOverlayWatermark = 'overlay_watermark';

  // 常规设置
  static const _keyStartupEnabled = 'general_startup';
  static const _keyThemeMode = 'general_theme'; // 'light' | 'dark'
  static const _keyFontFamily = 'general_font';

  final SharedPreferences _prefs;

  SettingsService(this._prefs);

  static Future<SettingsService> init() async {
    final prefs = await SharedPreferences.getInstance();
    return SettingsService(prefs);
  }

  // ─── 读取 ───

  double getBrightness() => _prefs.getDouble(_keyBrightness) ?? 0.0;

  double getAlpha() => _prefs.getDouble(_keyAlpha) ?? 0.3;

  Color getBaseColor() {
    final v = _prefs.getInt(_keyBaseColorValue);
    if (v == null) return Colors.transparent;
    return Color(v);
  }

  String? getActivePreset() => _prefs.getString(_keyActivePreset);

  List<Color> getRecentColors() {
    final list = _prefs.getStringList(_keyRecentColors);
    if (list == null || list.isEmpty) {
      return [
        Colors.transparent,
        const Color(0xFFFFB300),
        const Color(0xFF607D8B),
        const Color(0xFF795548),
        const Color(0xFF000000),
      ];
    }
    return list.map((s) => Color(int.parse(s))).toList();
  }

  // ─── 保存 ───

  Future<void> setBrightness(double v) => _prefs.setDouble(_keyBrightness, v);

  Future<void> setAlpha(double v) => _prefs.setDouble(_keyAlpha, v);

  Future<void> setBaseColor(Color c) =>
      // ignore: deprecated_member_use
      _prefs.setInt(_keyBaseColorValue, c.value);

  Future<void> setActivePreset(String? name) {
    if (name == null) return _prefs.remove(_keyActivePreset);
    return _prefs.setString(_keyActivePreset, name);
  }

  Future<void> setRecentColors(List<Color> colors) =>
      _prefs.setStringList(
        _keyRecentColors,
        // ignore: deprecated_member_use
        colors.map((c) => c.value.toString()).toList(),
      );

  // ─── 顶层组件 ───

  OverlayComponent getOverlayComponent(OverlayType type) {
    final key = _overlayKey(type);
    final json = _prefs.getString(key);
    if (json == null) {
      switch (type) {
        case OverlayType.clock:
          return OverlayComponent.createClock();
        case OverlayType.slogan:
          return OverlayComponent.createSlogan();
        case OverlayType.watermark:
          return OverlayComponent.createWatermark();
      }
    }
    return OverlayComponent.fromJson(
        jsonDecode(json) as Map<String, dynamic>);
  }

  Future<void> setOverlayComponent(OverlayComponent component) {
    final key = _overlayKey(component.type);
    return _prefs.setString(key, jsonEncode(component.toJson()));
  }

  String _overlayKey(OverlayType type) {
    switch (type) {
      case OverlayType.clock:
        return _keyOverlayClock;
      case OverlayType.slogan:
        return _keyOverlaySlogan;
      case OverlayType.watermark:
        return _keyOverlayWatermark;
    }
  }

  // ─── 常规设置 ───

  bool getStartupEnabled() => _prefs.getBool(_keyStartupEnabled) ?? false;
  String getThemeMode() => _prefs.getString(_keyThemeMode) ?? 'light';
  String getFontFamily() => _prefs.getString(_keyFontFamily) ?? 'Microsoft YaHei';

  Future<void> setStartupEnabled(bool v) => _prefs.setBool(_keyStartupEnabled, v);
  Future<void> setThemeMode(String v) => _prefs.setString(_keyThemeMode, v);
  Future<void> setFontFamily(String v) => _prefs.setString(_keyFontFamily, v);

  // ─── 高级功能 ───

  static const _keyFocusMode = 'advanced_focus_mode';
  static const _keySpotlight = 'advanced_spotlight';
  static const _keyAutomationRules = 'advanced_automation_rules';
  static const _keyAutomationEnabled = 'advanced_automation_enabled';
  static const _keyRegionMask = 'advanced_region_mask';

  FocusModeConfig getFocusModeConfig() {
    final json = _prefs.getString(_keyFocusMode);
    if (json == null) return FocusModeConfig();
    return FocusModeConfig.fromJson(jsonDecode(json));
  }

  SpotlightConfig getSpotlightConfig() {
    final json = _prefs.getString(_keySpotlight);
    if (json == null) return SpotlightConfig();
    return SpotlightConfig.fromJson(jsonDecode(json));
  }

  List<AutomationRule> getAutomationRules() {
    final json = _prefs.getString(_keyAutomationRules);
    if (json == null) return [];
    final list = jsonDecode(json) as List<dynamic>;
    return list.map((r) => AutomationRule.fromJson(r)).toList();
  }

  bool getAutomationEnabled() => _prefs.getBool(_keyAutomationEnabled) ?? false;

  Future<void> setFocusModeConfig(FocusModeConfig config) =>
      _prefs.setString(_keyFocusMode, jsonEncode(config.toJson()));

  Future<void> setSpotlightConfig(SpotlightConfig config) =>
      _prefs.setString(_keySpotlight, jsonEncode(config.toJson()));

  Future<void> setAutomationRules(List<AutomationRule> rules) =>
      _prefs.setString(_keyAutomationRules, jsonEncode(rules.map((r) => r.toJson()).toList()));

  Future<void> setAutomationEnabled(bool v) =>
      _prefs.setBool(_keyAutomationEnabled, v);

  RegionMaskConfig getRegionMaskConfig() {
    final json = _prefs.getString(_keyRegionMask);
    if (json == null) return RegionMaskConfig();
    return RegionMaskConfig.fromJson(jsonDecode(json));
  }

  Future<void> setRegionMaskConfig(RegionMaskConfig config) =>
      _prefs.setString(_keyRegionMask, jsonEncode(config.toJson()));

  // ─── 批量保存 ───

  Future<void> saveAll({
    required double brightness,
    required double alpha,
    required Color baseColor,
    String? activePreset,
    List<Color>? recentColors,
  }) async {
    await Future.wait([
      setBrightness(brightness),
      setAlpha(alpha),
      setBaseColor(baseColor),
      setActivePreset(activePreset),
      if (recentColors != null) setRecentColors(recentColors),
    ]);
  }
}
