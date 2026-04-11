import 'package:flutter/material.dart';

/// 专注模式配置
class FocusModeConfig {
  bool enabled;
  double dimOpacity;
  double borderRadius;

  FocusModeConfig({
    this.enabled = false,
    this.dimOpacity = 0.5,
    this.borderRadius = 8.0,
  });

  FocusModeConfig copyWith({
    bool? enabled,
    double? dimOpacity,
    double? borderRadius,
  }) =>
      FocusModeConfig(
        enabled: enabled ?? this.enabled,
        dimOpacity: dimOpacity ?? this.dimOpacity,
        borderRadius: borderRadius ?? this.borderRadius,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'dimOpacity': dimOpacity,
        'borderRadius': borderRadius,
      };

  factory FocusModeConfig.fromJson(Map<String, dynamic> json) =>
      FocusModeConfig(
        enabled: json['enabled'] ?? false,
        dimOpacity: (json['dimOpacity'] as num?)?.toDouble() ?? 0.5,
        borderRadius: (json['borderRadius'] as num?)?.toDouble() ?? 8.0,
      );
}

/// 聚光灯配置
class SpotlightConfig {
  bool enabled;
  double radius;
  double dimOpacity;
  double softEdge;

  SpotlightConfig({
    this.enabled = false,
    this.radius = 200.0,
    this.dimOpacity = 0.6,
    this.softEdge = 50.0,
  });

  SpotlightConfig copyWith({
    bool? enabled,
    double? radius,
    double? dimOpacity,
    double? softEdge,
  }) =>
      SpotlightConfig(
        enabled: enabled ?? this.enabled,
        radius: radius ?? this.radius,
        dimOpacity: dimOpacity ?? this.dimOpacity,
        softEdge: softEdge ?? this.softEdge,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'radius': radius,
        'dimOpacity': dimOpacity,
        'softEdge': softEdge,
      };

  factory SpotlightConfig.fromJson(Map<String, dynamic> json) =>
      SpotlightConfig(
        enabled: json['enabled'] ?? false,
        radius: (json['radius'] as num?)?.toDouble() ?? 200.0,
        dimOpacity: (json['dimOpacity'] as num?)?.toDouble() ?? 0.6,
        softEdge: (json['softEdge'] as num?)?.toDouble() ?? 50.0,
      );
}

/// 单个遮罩区域（多边形）
class MaskRegion {
  String id;
  String name;
  List<Offset> points; // 逻辑坐标
  bool enabled;

  MaskRegion({
    required this.id,
    this.name = '区域',
    required this.points,
    this.enabled = true,
  });

  MaskRegion copyWith({
    String? id,
    String? name,
    List<Offset>? points,
    bool? enabled,
  }) =>
      MaskRegion(
        id: id ?? this.id,
        name: name ?? this.name,
        points: points ?? this.points,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'points': points.map((p) => {'x': p.dx, 'y': p.dy}).toList(),
        'enabled': enabled,
      };

  factory MaskRegion.fromJson(Map<String, dynamic> json) => MaskRegion(
        id: json['id'] ?? '',
        name: json['name'] ?? '区域',
        points: (json['points'] as List<dynamic>?)
                ?.map((p) => Offset(
                      (p['x'] as num?)?.toDouble() ?? 0,
                      (p['y'] as num?)?.toDouble() ?? 0,
                    ))
                .toList() ??
            [],
        enabled: json['enabled'] ?? true,
      );
}

/// 区域遮罩配置
class RegionMaskConfig {
  bool enabled;
  List<MaskRegion> regions;
  bool inverted; // false=滤镜仅在区域内, true=滤镜在区域外

  RegionMaskConfig({
    this.enabled = false,
    List<MaskRegion>? regions,
    this.inverted = false,
  }) : regions = regions ?? [];

  RegionMaskConfig copyWith({
    bool? enabled,
    List<MaskRegion>? regions,
    bool? inverted,
  }) =>
      RegionMaskConfig(
        enabled: enabled ?? this.enabled,
        regions: regions ?? this.regions,
        inverted: inverted ?? this.inverted,
      );

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'regions': regions.map((r) => r.toJson()).toList(),
        'inverted': inverted,
      };

  factory RegionMaskConfig.fromJson(Map<String, dynamic> json) =>
      RegionMaskConfig(
        enabled: json['enabled'] ?? false,
        regions: (json['regions'] as List<dynamic>?)
                ?.map((r) => MaskRegion.fromJson(r as Map<String, dynamic>))
                .toList() ??
            [],
        inverted: json['inverted'] ?? false,
      );
}

/// 自动化规则
class AutomationRule {
  String processName;
  String presetName;
  bool enabled;

  AutomationRule({
    required this.processName,
    required this.presetName,
    this.enabled = true,
  });

  Map<String, dynamic> toJson() => {
        'processName': processName,
        'presetName': presetName,
        'enabled': enabled,
      };

  factory AutomationRule.fromJson(Map<String, dynamic> json) => AutomationRule(
        processName: json['processName'] ?? '',
        presetName: json['presetName'] ?? '',
        enabled: json['enabled'] ?? true,
      );
}

/// 完整的高级功能配置（用于导入导出）
class AppConfig {
  final double brightness;
  final double alpha;
  final Color baseColor;
  final String? activePreset;
  final List<Color> recentColors;
  final String fontFamily;
  final bool startupEnabled;
  final String themeMode;
  final FocusModeConfig focusMode;
  final SpotlightConfig spotlight;
  final RegionMaskConfig regionMask;
  final List<AutomationRule> automationRules;

  const AppConfig({
    this.brightness = 0.0,
    this.alpha = 0.3,
    this.baseColor = Colors.transparent,
    this.activePreset,
    this.recentColors = const [],
    this.fontFamily = 'Microsoft YaHei',
    this.startupEnabled = false,
    this.themeMode = 'light',
    this.focusMode = const _DefaultFocusMode(),
    this.spotlight = const _DefaultSpotlight(),
    this.regionMask = const _DefaultRegionMask(),
    this.automationRules = const [],
  });

  Map<String, dynamic> toJson() => {
        'version': '1.0',
        'exported_at': DateTime.now().toIso8601String(),
        'settings': {
          'brightness': brightness,
          'alpha': alpha,
          // ignore: deprecated_member_use
          'baseColor': baseColor.value,
          'activePreset': activePreset,
          // ignore: deprecated_member_use
          'recentColors': recentColors.map((c) => c.value).toList(),
          'fontFamily': fontFamily,
          'startupEnabled': startupEnabled,
          'themeMode': themeMode,
        },
        'focusMode': focusMode.toJson(),
        'spotlight': spotlight.toJson(),
        'regionMask': regionMask.toJson(),
        'automationRules': automationRules.map((r) => r.toJson()).toList(),
      };

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    final settings = json['settings'] as Map<String, dynamic>? ?? {};
    return AppConfig(
      brightness: (settings['brightness'] as num?)?.toDouble() ?? 0.0,
      alpha: (settings['alpha'] as num?)?.toDouble() ?? 0.3,
      baseColor: Color(settings['baseColor'] ?? 0x00000000),
      activePreset: settings['activePreset'] as String?,
      recentColors: (settings['recentColors'] as List<dynamic>?)
              ?.map((v) => Color(v as int))
              .toList() ??
          [],
      fontFamily: settings['fontFamily'] ?? 'Microsoft YaHei',
      startupEnabled: settings['startupEnabled'] ?? false,
      themeMode: settings['themeMode'] ?? 'light',
      focusMode: json['focusMode'] != null
          ? FocusModeConfig.fromJson(json['focusMode'])
          : FocusModeConfig(),
      spotlight: json['spotlight'] != null
          ? SpotlightConfig.fromJson(json['spotlight'])
          : SpotlightConfig(),
      regionMask: json['regionMask'] != null
          ? RegionMaskConfig.fromJson(json['regionMask'])
          : RegionMaskConfig(),
      automationRules: (json['automationRules'] as List<dynamic>?)
              ?.map((r) => AutomationRule.fromJson(r))
              .toList() ??
          [],
    );
  }
}

/// Sentinel for default const constructor.
class _DefaultFocusMode implements FocusModeConfig {
  const _DefaultFocusMode();
  @override
  bool get enabled => false;
  @override
  set enabled(bool _) {}
  @override
  double get dimOpacity => 0.5;
  @override
  set dimOpacity(double _) {}
  @override
  double get borderRadius => 8.0;
  @override
  set borderRadius(double _) {}
  @override
  FocusModeConfig copyWith({bool? enabled, double? dimOpacity, double? borderRadius}) =>
      FocusModeConfig(enabled: enabled ?? false, dimOpacity: dimOpacity ?? 0.5, borderRadius: borderRadius ?? 8.0);
  @override
  Map<String, dynamic> toJson() => {'enabled': false, 'dimOpacity': 0.5, 'borderRadius': 8.0};
}

class _DefaultSpotlight implements SpotlightConfig {
  const _DefaultSpotlight();
  @override
  bool get enabled => false;
  @override
  set enabled(bool _) {}
  @override
  double get radius => 200.0;
  @override
  set radius(double _) {}
  @override
  double get dimOpacity => 0.6;
  @override
  set dimOpacity(double _) {}
  @override
  double get softEdge => 50.0;
  @override
  set softEdge(double _) {}
  @override
  SpotlightConfig copyWith({bool? enabled, double? radius, double? dimOpacity, double? softEdge}) =>
      SpotlightConfig(enabled: enabled ?? false, radius: radius ?? 200.0, dimOpacity: dimOpacity ?? 0.6, softEdge: softEdge ?? 50.0);
  @override
  Map<String, dynamic> toJson() => {'enabled': false, 'radius': 200.0, 'dimOpacity': 0.6, 'softEdge': 50.0};
}

class _DefaultRegionMask implements RegionMaskConfig {
  const _DefaultRegionMask();
  @override
  bool get enabled => false;
  @override
  set enabled(bool _) {}
  @override
  List<MaskRegion> get regions => const [];
  @override
  set regions(List<MaskRegion> _) {}
  @override
  bool get inverted => false;
  @override
  set inverted(bool _) {}
  @override
  RegionMaskConfig copyWith({bool? enabled, List<MaskRegion>? regions, bool? inverted}) =>
      RegionMaskConfig(enabled: enabled ?? false, regions: regions ?? [], inverted: inverted ?? false);
  @override
  Map<String, dynamic> toJson() => {'enabled': false, 'regions': [], 'inverted': false};
}
