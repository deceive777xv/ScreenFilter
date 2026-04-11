#version 460 core
#extension GL_GOOGLE_include_directive : require
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;

uniform float uBrightness;
uniform float uAlpha;
uniform vec4 uBaseColor;

out vec4 fragColor;

void main() {
    vec4 finalColor = vec4(uBaseColor.rgb, uAlpha);

    if (uBrightness < 0.0) {
        float darkenAlpha = clamp(-uBrightness * 0.95, 0.0, 1.0);
        finalColor.rgb = mix(finalColor.rgb, vec3(0.0), darkenAlpha);
        finalColor.a = clamp(finalColor.a + darkenAlpha * 0.8, 0.0, 1.0);
    } else if (uBrightness > 0.0) {
        float lightenAlpha = clamp(uBrightness * 0.95, 0.0, 1.0);
        finalColor.rgb = mix(finalColor.rgb, vec3(1.0), lightenAlpha);
        finalColor.a = clamp(finalColor.a + lightenAlpha * 0.5, 0.0, 1.0);
    }

    fragColor = vec4(finalColor.rgb * finalColor.a, finalColor.a);
}
