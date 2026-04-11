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
}

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
    description: '暖黄色调减少蓝光',
    icon: Icons.visibility_outlined,
    baseColor: Color(0xFFFFB300),
    alpha: 0.15,
    brightness: 0.0,
    tileColor: Color(0xFFFFF3E0),
  ),
  FilterPreset(
    name: '夜间',
    description: '深色遮盖降低亮度',
    icon: Icons.dark_mode_outlined,
    baseColor: Color(0xFF000000),
    alpha: 0.4,
    brightness: -0.2,
    tileColor: Color(0xFFE0E0E0),
  ),
  FilterPreset(
    name: '电影',
    description: '青橙色调增强对比',
    icon: Icons.movie_filter_outlined,
    baseColor: Color(0xFF1A237E),
    alpha: 0.08,
    brightness: 0.05,
    tileColor: Color(0xFFE8EAF6),
  ),
  FilterPreset(
    name: '电子书',
    description: '仿纸张暖白色调',
    icon: Icons.menu_book_outlined,
    baseColor: Color(0xFFF5E6CA),
    alpha: 0.20,
    brightness: -0.05,
    tileColor: Color(0xFFFFF8E1),
  ),
  FilterPreset(
    name: '低蓝光',
    description: '降低蓝光保护视力',
    icon: Icons.remove_red_eye_outlined,
    baseColor: Color(0xFFFF8F00),
    alpha: 0.10,
    brightness: 0.0,
    tileColor: Color(0xFFFFF3E0),
  ),
  FilterPreset(
    name: '暖色',
    description: '柔和暖色调',
    icon: Icons.wb_sunny_outlined,
    baseColor: Color(0xFFFF6D00),
    alpha: 0.12,
    brightness: 0.02,
    tileColor: Color(0xFFFBE9E7),
  ),
  FilterPreset(
    name: '冷色',
    description: '清爽冷蓝色调',
    icon: Icons.ac_unit_outlined,
    baseColor: Color(0xFF42A5F5),
    alpha: 0.10,
    brightness: 0.0,
    tileColor: Color(0xFFE3F2FD),
  ),
  FilterPreset(
    name: '复古',
    description: '怀旧棕褐色调',
    icon: Icons.photo_filter_outlined,
    baseColor: Color(0xFF795548),
    alpha: 0.12,
    brightness: -0.03,
    tileColor: Color(0xFFEFEBE9),
  ),
  FilterPreset(
    name: '专注',
    description: '微暗环境减少干扰',
    icon: Icons.center_focus_strong_outlined,
    baseColor: Color(0xFF212121),
    alpha: 0.25,
    brightness: -0.1,
    tileColor: Color(0xFFEEEEEE),
  ),
  FilterPreset(
    name: '红绿色弱',
    description: '增强红绿对比度',
    icon: Icons.palette_outlined,
    baseColor: Color(0xFFE65100),
    alpha: 0.06,
    brightness: 0.03,
    tileColor: Color(0xFFFBE9E7),
  ),
  FilterPreset(
    name: '蓝黄色弱',
    description: '增强蓝黄对比度',
    icon: Icons.color_lens_outlined,
    baseColor: Color(0xFF0D47A1),
    alpha: 0.06,
    brightness: 0.03,
    tileColor: Color(0xFFE3F2FD),
  ),
];
