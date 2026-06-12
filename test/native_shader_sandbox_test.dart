import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:screen_filter_app/models/shader_preset.dart';

void main() {
  test('sandbox default shader demonstrates controlled screen sampling', () {
    expect(ShaderPreset.defaultShaderCode, contains('SampleScreen'));
    expect(ShaderPreset.defaultShaderCode, contains('offsetPx'));
    expect(ShaderPreset.defaultShaderCode, isNot(contains('Texture2D')));
  });

  test('native user shader path exposes a bounded screen sampling helper', () {
    final source = File(
      'native/dx11_shader_engine/src/shader_engine.cpp',
    ).readAsStringSync();
    final compileBody = _extractFunctionBody(source, 'CompileShaderToSlot');
    final renderUserBody = _extractFunctionBody(
      source,
      'RenderUserShaderToTarget',
    );

    expect(source, contains('kMaxSandboxScreenTextureWidth = 960'));
    expect(source, contains('kMaxSandboxScreenTextureHeight = 540'));
    expect(source, contains('kMaxScreenSampleRadiusPx = 32.0f'));
    expect(source, contains('kScreenTextureSandboxHeader'));
    expect(source, contains('Texture2D screenTexture : register(t0)'));
    expect(source, contains('float4 SampleScreen(float2 uv, float2 offsetPx)'));
    expect(source, contains('clamp(offsetPx'));

    expect(compileBody, contains('ValidateUserShaderSandbox'));
    expect(compileBody, contains('kScreenTextureSandboxHeader'));

    expect(renderUserBody, contains('PrepareSandboxScreenTexture'));
    expect(renderUserBody, contains('g_sandboxScreenSrv'));
    expect(renderUserBody, contains('g_screenTextureCbuffer'));
    expect(renderUserBody, contains('PSSetConstantBuffers(3'));
  });
}

String _extractFunctionBody(String source, String functionName) {
  var searchFrom = 0;
  late int openBrace;
  while (true) {
    final start = source.indexOf(functionName, searchFrom);
    if (start < 0) {
      fail('Could not find $functionName');
    }
    openBrace = source.indexOf('{', start);
    if (openBrace < 0) {
      fail('Could not find $functionName body');
    }
    final semicolon = source.indexOf(';', start);
    if (semicolon < 0 || semicolon > openBrace) {
      break;
    }
    searchFrom = semicolon + 1;
  }

  var depth = 0;
  for (var i = openBrace; i < source.length; i++) {
    final char = source[i];
    if (char == '{') depth++;
    if (char == '}') {
      depth--;
      if (depth == 0) {
        return source.substring(openBrace, i + 1);
      }
    }
  }
  fail('Could not parse $functionName body');
}
