import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

/// Data model for a .shader preset file.
class ShaderPreset {
  String name;
  String author;
  String description;
  String code;
  DateTime created;
  List<String> tags;
  Color accentColor;

  ShaderPreset({
    required this.name,
    this.author = '',
    this.description = '',
    required this.code,
    DateTime? created,
    this.tags = const [],
    this.accentColor = const Color(0xFFFF8040),
  }) : created = created ?? DateTime.now();

  /// Default HLSL template for new shaders in the sandbox.
  static const String defaultShaderCode = r'''// ScreenFilter Shader Sandbox
//
// Available uniforms (cbuffer Uniforms : register(b0)):
//   u_Time        : float  - Elapsed time (seconds)
//   u_Resolution  : float2 - Viewport resolution (width, height)
//   u_Mouse       : float2 - Mouse position (normalized 0~1)
//   u_AccentColor : float4 - User accent color (RGBA)

cbuffer Uniforms : register(b0) {
    float  u_Time;
    float3 _pad0;
    float2 u_Resolution;
    float2 u_Mouse;
    float4 u_AccentColor;
};

struct PS_INPUT {
    float4 pos : SV_POSITION;
    float2 uv  : TEXCOORD0;
};

float4 main(PS_INPUT input) : SV_TARGET {
    float2 uv = input.uv;

    // Aspect-correct coordinates centered at origin
    float2 p = (2.0 * uv - 1.0);
    p.x *= u_Resolution.x / u_Resolution.y;

    // Animated color gradient (Shadertoy style)
    float3 col = 0.5 + 0.5 * cos(u_Time + uv.xyx + float3(0, 2, 4));

    // Mouse influence: radial glow
    float2 m = (2.0 * u_Mouse - 1.0);
    m.x *= u_Resolution.x / u_Resolution.y;
    float d = length(p - m);
    col += u_AccentColor.rgb * 0.3 * exp(-3.0 * d);

    return float4(col, 1.0);
}
''';

  Map<String, dynamic> toJson() {
    return {
      'format': 'screenfilter-shader',
      'version': '1.0',
      'metadata': {
        'name': name,
        'author': author,
        'description': description,
        'created': created.toIso8601String(),
        'tags': tags,
      },
      'shader': {
        'language': 'hlsl',
        'code': code,
      },
      'uniforms': {
        'u_AccentColor': [
          accentColor.r,
          accentColor.g,
          accentColor.b,
          accentColor.a,
        ],
      },
    };
  }

  factory ShaderPreset.fromJson(Map<String, dynamic> json) {
    final metadata = json['metadata'] as Map<String, dynamic>? ?? {};
    final shader = json['shader'] as Map<String, dynamic>? ?? {};
    final uniforms = json['uniforms'] as Map<String, dynamic>? ?? {};

    Color accent = const Color(0xFFFF8040);
    if (uniforms.containsKey('u_AccentColor')) {
      final c = uniforms['u_AccentColor'] as List;
      accent = Color.fromARGB(
        ((c.length > 3 ? c[3] : 1.0) as num).toDouble().clamp(0, 1).toDouble() * 255 ~/ 1,
        ((c[0] as num).toDouble().clamp(0, 1) * 255).toInt(),
        ((c[1] as num).toDouble().clamp(0, 1) * 255).toInt(),
        ((c[2] as num).toDouble().clamp(0, 1) * 255).toInt(),
      );
    }

    return ShaderPreset(
      name: metadata['name'] ?? 'Untitled',
      author: metadata['author'] ?? '',
      description: metadata['description'] ?? '',
      code: shader['code'] ?? defaultShaderCode,
      created: DateTime.tryParse(metadata['created'] ?? '') ?? DateTime.now(),
      tags: List<String>.from(metadata['tags'] ?? []),
      accentColor: accent,
    );
  }

  /// Export to a .shader file (JSON format).
  Future<void> exportToFile(String filePath) async {
    final jsonStr = const JsonEncoder.withIndent('  ').convert(toJson());
    await File(filePath).writeAsString(jsonStr);
  }

  /// Import from a .shader file.
  static Future<ShaderPreset> importFromFile(String filePath) async {
    final content = await File(filePath).readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;
    return ShaderPreset.fromJson(json);
  }
}
