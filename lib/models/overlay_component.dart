import 'package:flutter/material.dart';

/// 顶层组件类型
enum OverlayType { clock, slogan, watermark }

/// 时钟样式
enum ClockStyle { digital, analog }

/// 时钟组件配置
class ClockConfig {
  final ClockStyle style;
  final double fontSize;
  final Color color;
  final bool showSeconds;
  final bool show24Hour;

  const ClockConfig({
    this.style = ClockStyle.digital,
    this.fontSize = 48,
    this.color = Colors.white,
    this.showSeconds = true,
    this.show24Hour = true,
  });

  ClockConfig copyWith({
    ClockStyle? style,
    double? fontSize,
    Color? color,
    bool? showSeconds,
    bool? show24Hour,
  }) {
    return ClockConfig(
      style: style ?? this.style,
      fontSize: fontSize ?? this.fontSize,
      color: color ?? this.color,
      showSeconds: showSeconds ?? this.showSeconds,
      show24Hour: show24Hour ?? this.show24Hour,
    );
  }

  Map<String, dynamic> toJson() => {
        'style': style.index,
        'fontSize': fontSize,
        'color': color.value,
        'showSeconds': showSeconds,
        'show24Hour': show24Hour,
      };

  factory ClockConfig.fromJson(Map<String, dynamic> json) => ClockConfig(
        style: ClockStyle.values[json['style'] as int? ?? 0],
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? 48,
        color: Color(json['color'] as int? ?? 0xFFFFFFFF),
        showSeconds: json['showSeconds'] as bool? ?? true,
        show24Hour: json['show24Hour'] as bool? ?? true,
      );
}

/// 标语组件配置
class SloganConfig {
  final String text;
  final double fontSize;
  final Color color;
  final String fontFamily;
  final FontWeight fontWeight;

  const SloganConfig({
    this.text = 'Stay Focused',
    this.fontSize = 36,
    this.color = Colors.white,
    this.fontFamily = 'Microsoft YaHei',
    this.fontWeight = FontWeight.bold,
  });

  SloganConfig copyWith({
    String? text,
    double? fontSize,
    Color? color,
    String? fontFamily,
    FontWeight? fontWeight,
  }) {
    return SloganConfig(
      text: text ?? this.text,
      fontSize: fontSize ?? this.fontSize,
      color: color ?? this.color,
      fontFamily: fontFamily ?? this.fontFamily,
      fontWeight: fontWeight ?? this.fontWeight,
    );
  }

  Map<String, dynamic> toJson() => {
        'text': text,
        'fontSize': fontSize,
        'color': color.value,
        'fontFamily': fontFamily,
        'fontWeight': fontWeight.index,
      };

  factory SloganConfig.fromJson(Map<String, dynamic> json) => SloganConfig(
        text: json['text'] as String? ?? 'Stay Focused',
        fontSize: (json['fontSize'] as num?)?.toDouble() ?? 36,
        color: Color(json['color'] as int? ?? 0xFFFFFFFF),
        fontFamily: json['fontFamily'] as String? ?? 'Microsoft YaHei',
        fontWeight: FontWeight.values[json['fontWeight'] as int? ?? 7],
      );
}

/// 水印组件配置
class WatermarkConfig {
  final String imagePath;
  final double width;
  final double height;
  final double opacity;

  const WatermarkConfig({
    this.imagePath = '',
    this.width = 200,
    this.height = 200,
    this.opacity = 0.5,
  });

  WatermarkConfig copyWith({
    String? imagePath,
    double? width,
    double? height,
    double? opacity,
  }) {
    return WatermarkConfig(
      imagePath: imagePath ?? this.imagePath,
      width: width ?? this.width,
      height: height ?? this.height,
      opacity: opacity ?? this.opacity,
    );
  }

  Map<String, dynamic> toJson() => {
        'imagePath': imagePath,
        'width': width,
        'height': height,
        'opacity': opacity,
      };

  factory WatermarkConfig.fromJson(Map<String, dynamic> json) =>
      WatermarkConfig(
        imagePath: json['imagePath'] as String? ?? '',
        width: (json['width'] as num?)?.toDouble() ?? 200,
        height: (json['height'] as num?)?.toDouble() ?? 200,
        opacity: (json['opacity'] as num?)?.toDouble() ?? 0.5,
      );
}

/// 顶层组件通用模型
class OverlayComponent {
  final OverlayType type;
  bool enabled;
  Offset position;

  // 具体配置（根据 type 使用对应类型）
  ClockConfig? clockConfig;
  SloganConfig? sloganConfig;
  WatermarkConfig? watermarkConfig;

  OverlayComponent({
    required this.type,
    this.enabled = false,
    this.position = const Offset(100, 100),
    this.clockConfig,
    this.sloganConfig,
    this.watermarkConfig,
  });

  Map<String, dynamic> toJson() => {
        'type': type.index,
        'enabled': enabled,
        'posX': position.dx,
        'posY': position.dy,
        if (clockConfig != null) 'clockConfig': clockConfig!.toJson(),
        if (sloganConfig != null) 'sloganConfig': sloganConfig!.toJson(),
        if (watermarkConfig != null)
          'watermarkConfig': watermarkConfig!.toJson(),
      };

  factory OverlayComponent.fromJson(Map<String, dynamic> json) {
    final type = OverlayType.values[json['type'] as int];
    return OverlayComponent(
      type: type,
      enabled: json['enabled'] as bool? ?? false,
      position: Offset(
        (json['posX'] as num?)?.toDouble() ?? 100,
        (json['posY'] as num?)?.toDouble() ?? 100,
      ),
      clockConfig: json['clockConfig'] != null
          ? ClockConfig.fromJson(json['clockConfig'] as Map<String, dynamic>)
          : (type == OverlayType.clock ? const ClockConfig() : null),
      sloganConfig: json['sloganConfig'] != null
          ? SloganConfig.fromJson(json['sloganConfig'] as Map<String, dynamic>)
          : (type == OverlayType.slogan ? const SloganConfig() : null),
      watermarkConfig: json['watermarkConfig'] != null
          ? WatermarkConfig.fromJson(
              json['watermarkConfig'] as Map<String, dynamic>)
          : (type == OverlayType.watermark ? const WatermarkConfig() : null),
    );
  }

  /// 工厂方法
  static OverlayComponent createClock() => OverlayComponent(
        type: OverlayType.clock,
        clockConfig: const ClockConfig(),
      );

  static OverlayComponent createSlogan() => OverlayComponent(
        type: OverlayType.slogan,
        sloganConfig: const SloganConfig(),
      );

  static OverlayComponent createWatermark() => OverlayComponent(
        type: OverlayType.watermark,
        watermarkConfig: const WatermarkConfig(),
      );
}
