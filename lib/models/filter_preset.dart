import 'package:flutter/material.dart';

/// 滤镜预设数据模型
class FilterPreset {
  final String name;
  final String description;
  final IconData icon;
  final Color baseColor;
  final double alpha;
  final double brightness;
  final Color tileColor; // 磁贴背景色

  const FilterPreset({
    required this.name,
    required this.description,
    required this.icon,
    required this.baseColor,
    required this.alpha,
    required this.brightness,
    required this.tileColor,
  });

  double get effectiveOverlayAlpha {
    if (brightness < 0.0) {
      final darkenAlpha = (-brightness * 0.95).clamp(0.0, 1.0);
      return (alpha + darkenAlpha * 0.8).clamp(0.0, 1.0);
    }
    if (brightness > 0.0) {
      final lightenAlpha = (brightness * 0.95).clamp(0.0, 1.0);
      return (alpha + lightenAlpha * 0.5).clamp(0.0, 1.0);
    }
    return alpha.clamp(0.0, 1.0);
  }

  Color get effectiveOverlayColor {
    final mixTarget = brightness < 0.0
        ? Colors.black
        : brightness > 0.0
        ? Colors.white
        : null;
    final mixAmount = (brightness.abs() * 0.95).clamp(0.0, 1.0);
    final color = mixTarget == null
        ? baseColor
        : _mixRgb(baseColor, mixTarget, mixAmount);
    return Color.fromARGB(
      (effectiveOverlayAlpha * 255).round().clamp(0, 255),
      _redOf(color),
      _greenOf(color),
      _blueOf(color),
    );
  }
}

FilterPreset? basicFilterPresetByName(String name) {
  for (final preset in kBasicFilterPresets) {
    if (preset.name == name) return preset;
  }
  return null;
}

Color _mixRgb(Color color, Color target, double amount) {
  return Color.fromARGB(
    255,
    _mixChannel(_redOf(color), _redOf(target), amount),
    _mixChannel(_greenOf(color), _greenOf(target), amount),
    _mixChannel(_blueOf(color), _blueOf(target), amount),
  );
}

int _mixChannel(int source, int target, double amount) {
  return (source + (target - source) * amount).round().clamp(0, 255);
}

int _redOf(Color color) => (color.toARGB32() >> 16) & 0xFF;
int _greenOf(Color color) => (color.toARGB32() >> 8) & 0xFF;
int _blueOf(Color color) => color.toARGB32() & 0xFF;

/// ─── 基础滤镜预设 ───
const List<FilterPreset> kBasicFilterPresets = [
  FilterPreset(
    name: '清除',
    description: '关闭所有滤镜',
    icon: Icons.block_outlined,
    baseColor: Colors.transparent,
    alpha: 0.0,
    brightness: 0.0,
    tileColor: Color(0xFFF0F0F0),
  ),
  FilterPreset(
    name: '护眼',
    description: '柔和暖黄，减轻冷白刺眼感',
    icon: Icons.visibility_outlined,
    baseColor: Color(0xFFFFC857),
    alpha: 0.11,
    brightness: -0.02,
    tileColor: Color(0xFFFFF3E0),
  ),
  FilterPreset(
    name: '夜间',
    description: '中性压暗，适合低光环境',
    icon: Icons.dark_mode_outlined,
    baseColor: Color(0xFF000000),
    alpha: 0.24,
    brightness: -0.16,
    tileColor: Color(0xFFE0E0E0),
  ),
  FilterPreset(
    name: '电影',
    description: '轻微冷调，压低刺眼高光',
    icon: Icons.movie_filter_outlined,
    baseColor: Color(0xFF243B6B),
    alpha: 0.06,
    brightness: -0.03,
    tileColor: Color(0xFFE8EAF6),
  ),
  FilterPreset(
    name: '电子书',
    description: '仿纸张暖白色调',
    icon: Icons.menu_book_outlined,
    baseColor: Color(0xFFFFE8C2),
    alpha: 0.13,
    brightness: -0.02,
    tileColor: Color(0xFFFFF8E1),
  ),
  FilterPreset(
    name: '低蓝光',
    description: '更强暖黄，减少冷色占比',
    icon: Icons.remove_red_eye_outlined,
    baseColor: Color(0xFFFFA726),
    alpha: 0.16,
    brightness: -0.04,
    tileColor: Color(0xFFFFF3E0),
  ),
  FilterPreset(
    name: '暖色',
    description: '柔和暖色调',
    icon: Icons.wb_sunny_outlined,
    baseColor: Color(0xFFFF8A3D),
    alpha: 0.09,
    brightness: 0.0,
    tileColor: Color(0xFFFBE9E7),
  ),
  FilterPreset(
    name: '冷色',
    description: '清爽冷蓝色调',
    icon: Icons.ac_unit_outlined,
    baseColor: Color(0xFF64B5F6),
    alpha: 0.07,
    brightness: 0.0,
    tileColor: Color(0xFFE3F2FD),
  ),
  FilterPreset(
    name: '复古',
    description: '怀旧棕褐色调',
    icon: Icons.photo_filter_outlined,
    baseColor: Color(0xFF8D6E63),
    alpha: 0.10,
    brightness: -0.02,
    tileColor: Color(0xFFEFEBE9),
  ),
  FilterPreset(
    name: '专注',
    description: '微暗环境减少干扰',
    icon: Icons.center_focus_strong_outlined,
    baseColor: Color(0xFF111827),
    alpha: 0.18,
    brightness: -0.12,
    tileColor: Color(0xFFEEEEEE),
  ),
  FilterPreset(
    name: '红绿色弱',
    description: '暖调轻提亮，不替代色弱校正',
    icon: Icons.palette_outlined,
    baseColor: Color(0xFFFFD54F),
    alpha: 0.06,
    brightness: 0.02,
    tileColor: Color(0xFFFBE9E7),
  ),
  FilterPreset(
    name: '蓝黄色弱',
    description: '冷调轻提亮，不替代色弱校正',
    icon: Icons.color_lens_outlined,
    baseColor: Color(0xFF90CAF9),
    alpha: 0.05,
    brightness: 0.02,
    tileColor: Color(0xFFE3F2FD),
  ),
];
