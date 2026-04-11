import 'package:flutter/material.dart';

/// 内置屏幕特效预设（通过 DX11 HLSL 渲染）
class ScreenEffect {
  final String name;
  final String description;
  final IconData icon;
  final Color tileColor;
  final Color iconColor;
  final String hlslCode;

  const ScreenEffect({
    required this.name,
    required this.description,
    required this.icon,
    required this.tileColor,
    required this.iconColor,
    required this.hlslCode,
  });
}

// ─── HLSL 头部（所有特效共用）───────────────────────────────────────
const _kHeader = r'''cbuffer Uniforms : register(b0) {
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

float hash1(float n)  { return frac(sin(n) * 43758.5453); }
float hash2(float2 p) { return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }

''';

// ─── 雪花 ───────────────────────────────────────────────────────────
// 60 颗白色雪花从屏幕顶部随机飘落，带左右摇摆
const _kSnowCode = _kHeader + r'''
float4 main(PS_INPUT input) : SV_TARGET {
    float2 uv    = input.uv;
    float aspect = u_Resolution.x / u_Resolution.y;
    float a      = 0.0;

    [loop] for (int i = 0; i < 60; i++) {
        float fi    = float(i);
        float speed = 0.05 + hash1(fi * 3.71) * 0.12;
        float size  = 0.004 + hash1(fi * 2.31) * 0.006;
        float col_x = hash1(fi * 1.93);
        float offset= hash1(fi * 5.17);
        float y     = frac(offset - u_Time * speed);
        float drift = sin(u_Time * 0.35 + fi * 0.83) * 0.018;
        float2 sp   = float2(col_x + drift, y);
        float2 d    = uv - sp;
        d.x        *= aspect;
        a          += smoothstep(size, 0.0, length(d));
    }
    return float4(1.0, 1.0, 1.0, saturate(a));
}
''';

// ─── 星星（菱形 + 光晕）────────────────────────────────────────────
// 80 颗随机散布，使用菱形 SDF 呈现钻石形，带闪烁和柔和光晕
const _kStarsCode = _kHeader + r'''
float4 main(PS_INPUT input) : SV_TARGET {
    float2 uv = input.uv;
    float aspect = u_Resolution.x / u_Resolution.y;
    float3 col = float3(0.0, 0.0, 0.0);
    float  a   = 0.0;

    [loop] for (int i = 0; i < 80; i++) {
        float fi   = float(i);
        float sx   = hash1(fi * 1.31);
        float sy   = hash1(fi * 2.79);
        float sz   = 0.005 + hash1(fi * 3.07) * 0.007;
        float blink= saturate(0.5 + 0.5 * sin(
                         u_Time * (0.6 + hash1(fi * 4.13) * 2.4) + fi * 1.37));

        float2 p   = uv - float2(sx, sy);
        p.x       *= aspect;
        float  r   = length(p);

        // 菱形 SDF：abs(x) + abs(y) = r_diamond
        float dDiamond = (abs(p.x) + abs(p.y)) / sz;
        float sparkle  = smoothstep(1.0, 0.1, dDiamond) * blink;

        // 柔和圆形光晕
        float glow = exp(-r * r / (sz * sz * 22.0)) * blink * 0.45;

        float3 sc  = lerp(float3(0.82, 0.93, 1.00),
                          float3(1.00, 0.97, 0.72),
                          hash1(fi * 5.11));
        col += sc * (sparkle + glow);
        a   += sparkle * 0.9 + glow;
    }

    return float4(saturate(col), saturate(a));
}
''';

// ─── 萤火虫 ─────────────────────────────────────────────────────────
// 30 个温暖金绿色光点，沿平滑 Lissajous 轨迹缓慢漂浮，带渐隐效果
const _kFirefliesCode = _kHeader + r'''
float4 main(PS_INPUT input) : SV_TARGET {
    float2 uv  = input.uv;
    float aspect = u_Resolution.x / u_Resolution.y;
    uv.x *= aspect;

    float3 col = float3(0.0, 0.0, 0.0);
    float  a   = 0.0;

    [loop] for (int i = 0; i < 30; i++) {
        float fi   = float(i);

        // 基础锚点 + Lissajous 漂移
        float bx   = hash1(fi * 1.43);
        float by   = hash1(fi * 2.87);
        float ampX = 0.04 + hash1(fi * 7.11) * 0.07;
        float ampY = 0.03 + hash1(fi * 8.23) * 0.06;
        float frqX = 0.11 + hash1(fi * 3.17) * 0.18;
        float frqY = 0.09 + hash1(fi * 4.23) * 0.14;
        float phX  = hash1(fi * 5.39) * 6.2832;
        float phY  = hash1(fi * 6.61) * 6.2832;

        float2 pos = float2(bx + sin(u_Time * frqX + phX) * ampX,
                            by + sin(u_Time * frqY + phY) * ampY);

        // 缓慢呼吸式亮度
        float blink = saturate(0.35 + 0.65 * (0.5 + 0.5 * sin(
                          u_Time * (0.7 + hash1(fi * 9.17) * 1.6) + fi * 2.3)));

        float2 delta = uv - pos;
        float  dist  = length(delta);

        // 柔和光晕（覆盖约 20–30px）
        float glow = exp(-dist * dist * 14000.0) * blink;
        // 明亮核心（约 4px）
        float core = smoothstep(0.004, 0.0, dist) * blink * 2.5;

        // 金黄绿色系
        float ct   = hash1(fi * 11.37);
        float3 fc  = lerp(float3(0.62, 1.00, 0.15),
                          float3(1.00, 0.88, 0.08), ct);

        col += fc * (glow + core);
        a   += glow * 0.45 + core * 0.35;
    }

    return float4(saturate(col), saturate(a));
}
''';

// ─── 极光 ───────────────────────────────────────────────────────────
// 5 条彩色光带在屏幕顶部缓慢涌动（绿→青→蓝→紫），仿北极光
const _kAuroraCode = _kHeader + r'''
float3 auroraPalette(float fi) {
    float t = fi / 4.0;
    float3 c0 = float3(0.08, 0.95, 0.40);   // 绿
    float3 c1 = float3(0.05, 0.80, 0.78);   // 青
    float3 c2 = float3(0.15, 0.52, 1.00);   // 蓝
    float3 c3 = float3(0.55, 0.22, 1.00);   // 紫
    float3 c4 = float3(0.90, 0.15, 0.85);   // 粉紫
    float3 c;
    if      (t < 0.25) c = lerp(c0, c1, t * 4.0);
    else if (t < 0.50) c = lerp(c1, c2, (t - 0.25) * 4.0);
    else if (t < 0.75) c = lerp(c2, c3, (t - 0.50) * 4.0);
    else               c = lerp(c3, c4, (t - 0.75) * 4.0);
    return c;
}

float4 main(PS_INPUT input) : SV_TARGET {
    float2 uv    = input.uv;

    // 屏幕上方 40% 可见，向中心渐隐
    float yFade  = smoothstep(0.42, 0.0, uv.y);
    if (yFade < 0.001) return float4(0, 0, 0, 0);

    float3 col   = float3(0, 0, 0);
    float  a     = 0.0;
    float  wSum  = 0.0;

    [loop] for (int i = 0; i < 5; i++) {
        float fi   = float(i);
        float ph1  = hash1(fi * 1.37) * 6.2832;
        float ph2  = hash1(fi * 2.71) * 6.2832;
        float ph3  = hash1(fi * 3.59) * 6.2832;

        // 多频率波动
        float baseY = 0.05 + fi * 0.07;
        float waveY = baseY
            + sin(uv.x * 3.5 + u_Time * 0.27 + ph1) * 0.033
            + sin(uv.x * 8.0 + u_Time * 0.17 + ph2) * 0.013
            + sin(uv.x * 16.0+ u_Time * 0.10 + ph3) * 0.006;

        // 沿 x 方向变化的厚度
        float thick = 0.048 + sin(uv.x * 5.0 + u_Time * 0.12 + ph1 * 0.5) * 0.018;
        float dist  = abs(uv.y - waveY);
        float band  = smoothstep(thick, thick * 0.05, dist);

        // 亮度呼吸
        float flick = 0.65 + 0.35 * sin(u_Time * (0.32 + hash1(fi * 4.13) * 0.25) + ph3);

        float3 c    = auroraPalette(fi);
        float  w    = band * flick;
        col  += c * w;
        a    += w * 0.55;
        wSum += w;
    }

    float finalA   = saturate(a * yFade * 0.85);
    float3 finalC  = wSum > 0.001 ? saturate(col / wSum) : float3(0.1, 0.9, 0.4);
    return float4(finalC, finalA);
}
''';

// ─── 阳光 ───────────────────────────────────────────────────────────
// 10 条金色光束从屏幕上方散射，带呼吸闪烁
const _kSunbeamsCode = _kHeader + r'''
float4 main(PS_INPUT input) : SV_TARGET {
    float2 uv    = input.uv;
    float aspect = u_Resolution.x / u_Resolution.y;

    float2 sunPos = float2(0.5, -0.15);
    float2 dir    = uv - sunPos;
    dir.x        *= aspect;
    float  dist   = length(dir);
    float  angle  = atan2(dir.x, dir.y);

    float rays = 0.0;
    [loop] for (int i = 0; i < 10; i++) {
        float fi    = float(i);
        float rayA  = hash1(fi * 1.73) * 3.14159 * 2.0;
        float width = 0.022 + hash1(fi * 2.37) * 0.050;
        float diff  = abs(fmod(angle - rayA + 9.4248, 6.2832) - 3.14159);
        float beam  = smoothstep(width, 0.0, diff);
        beam       *= smoothstep(1.6, 0.0, dist);
        float bVar  = 0.55 + 0.45 * sin(u_Time * 0.22 + fi * 1.91);
        rays       += beam * bVar;
    }

    float3 col = float3(1.0, 0.93, 0.50);
    return float4(col, saturate(rays * 0.32));
}
''';

// ─── 内置特效列表 ────────────────────────────────────────────────────
const List<ScreenEffect> kScreenEffects = [
  ScreenEffect(
    name: '雪花',
    description: '漫天飘落的雪花',
    icon: Icons.ac_unit_rounded,
    tileColor: Color(0xFFE3F2FD),
    iconColor: Color(0xFF2196F3),
    hlslCode: _kSnowCode,
  ),
  ScreenEffect(
    name: '星星',
    description: '菱形闪烁繁星',
    icon: Icons.auto_awesome,
    tileColor: Color(0xFFFFF8E1),
    iconColor: Color(0xFFFFB300),
    hlslCode: _kStarsCode,
  ),
  ScreenEffect(
    name: '萤火虫',
    description: '温暖金绿光点漂浮',
    icon: Icons.lens_blur,
    tileColor: Color(0xFFF1F8E9),
    iconColor: Color(0xFF7CB342),
    hlslCode: _kFirefliesCode,
  ),
  ScreenEffect(
    name: '极光',
    description: '彩色光带仿北极光',
    icon: Icons.gradient,
    tileColor: Color(0xFFEDE7F6),
    iconColor: Color(0xFF7E57C2),
    hlslCode: _kAuroraCode,
  ),
  ScreenEffect(
    name: '阳光',
    description: '温暖金色光束散射',
    icon: Icons.wb_sunny_rounded,
    tileColor: Color(0xFFFFF3E0),
    iconColor: Color(0xFFFF9800),
    hlslCode: _kSunbeamsCode,
  ),
];
