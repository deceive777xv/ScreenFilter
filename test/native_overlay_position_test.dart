import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'native overlay is placed behind Flutter once Flutter window appears',
    () {
      final source = File(
        'native/dx11_shader_engine/src/shader_engine.cpp',
      ).readAsStringSync();
      final positionBody = _extractFunctionBody(
        source,
        'PositionOverlayWindow',
      );
      final releaseBody = _extractFunctionBody(
        source,
        'ReleaseOverlayResources',
      );

      expect(positionBody, contains('g_overlayPlacedBehindFlutter'));
      expect(positionBody, contains('g_overlayRelativeFlutterWindow'));
      expect(
        positionBody,
        contains('g_overlayRelativeFlutterWindow == flutterWindow'),
      );
      expect(
        positionBody,
        contains('g_overlayPlacedBehindFlutter = flutterWindow != nullptr'),
      );
      expect(releaseBody, contains('g_overlayPlacedBehindFlutter = false'));
      expect(releaseBody, contains('g_overlayRelativeFlutterWindow = nullptr'));
    },
  );

  test('native overlay is shown only after the first presented frame', () {
    final source = File(
      'native/dx11_shader_engine/src/shader_engine.cpp',
    ).readAsStringSync();
    final createWindowBody = _extractFunctionBody(
      source,
      'CreateOverlayWindow',
    );
    final positionBody = _extractFunctionBody(source, 'PositionOverlayWindow');
    final renderCompositeBody = _extractFunctionBody(
      source,
      'RenderCompositeToOverlay',
    );
    final showAfterFirstFrameBody = _extractFunctionBody(
      source,
      'ShowOverlayWindowAfterFirstFrame',
    );
    final releaseBody = _extractFunctionBody(source, 'ReleaseOverlayResources');

    expect(createWindowBody, isNot(contains('ShowWindow')));
    expect(positionBody, contains('showWindow'));
    expect(positionBody, contains('SWP_SHOWWINDOW'));
    expect(renderCompositeBody, contains('ShowOverlayWindowAfterFirstFrame'));
    expect(
      showAfterFirstFrameBody,
      contains('g_overlayHasPresentedFrame = true'),
    );
    expect(releaseBody, contains('g_overlayHasPresentedFrame = false'));
  });

  test('native overlay is excluded from screen capture feedback', () {
    final source = File(
      'native/dx11_shader_engine/src/shader_engine.cpp',
    ).readAsStringSync();
    final createWindowBody = _extractFunctionBody(
      source,
      'CreateOverlayWindow',
    );

    expect(source, contains('WDA_EXCLUDEFROMCAPTURE'));
    expect(createWindowBody, contains('SetWindowDisplayAffinity'));
    expect(createWindowBody, contains('WDA_EXCLUDEFROMCAPTURE'));
  });

  test('native screen capture excludes the Flutter host window', () {
    final source = File(
      'native/dx11_shader_engine/src/shader_engine.cpp',
    ).readAsStringSync();
    final captureBody = _extractFunctionBody(source, 'CaptureScreenFrame');
    final excludeBody = _extractFunctionBody(
      source,
      'EnsureFlutterWindowExcludedFromCapture',
    );

    expect(source, contains('g_captureExcludedFlutterWindow'));
    expect(captureBody, contains('EnsureFlutterWindowExcludedFromCapture'));
    expect(excludeBody, contains('FindFlutterWindowCached'));
    expect(excludeBody, contains('SetWindowDisplayAffinity'));
    expect(excludeBody, contains('WDA_EXCLUDEFROMCAPTURE'));
  });

  test('native preview reuses recent fullscreen screen texture', () {
    final source = File(
      'native/dx11_shader_engine/src/shader_engine.cpp',
    ).readAsStringSync();
    final renderUserShaderBody = _extractFunctionBody(
      source,
      'RenderUserShaderToTarget',
    );
    final previewBody = _extractFunctionBody(
      source,
      'engine_render_preview_frame',
    );
    final overlayBody = _extractFunctionBody(
      source,
      'engine_render_overlay_frame',
    );
    final releaseBody = _extractFunctionBody(source, 'ReleaseOverlayResources');

    expect(source, contains('ScreenTextureUpdateMode'));
    expect(source, contains('ShouldPreviewReuseActiveScreenTexture'));
    expect(source, contains('g_lastOverlayRenderTick'));
    expect(renderUserShaderBody, contains('ScreenTextureUpdateMode::ReuseLatest'));
    expect(renderUserShaderBody, contains('PrepareSandboxScreenTexture'));
    expect(previewBody, contains('ShouldPreviewReuseActiveScreenTexture'));
    expect(previewBody, contains('ScreenTextureUpdateMode::ReuseLatest'));
    expect(overlayBody, contains('g_lastOverlayRenderTick = GetTickCount64()'));
    expect(releaseBody, contains('g_lastOverlayRenderTick = 0'));
  });

  test('native preview rendering uses resources separate from fullscreen', () {
    final source = File(
      'native/dx11_shader_engine/src/shader_engine.cpp',
    ).readAsStringSync();
    final fullscreenBody = _extractFunctionBody(source, 'engine_render_frame');
    final previewBody = _extractFunctionBody(
      source,
      'engine_render_preview_frame',
    );
    final overlayBody = _extractFunctionBody(
      source,
      'engine_render_overlay_frame',
    );
    final pixelReadbackBody = _extractFunctionBody(
      source,
      'engine_get_frame_pixels',
    );

    expect(source, contains('g_previewRenderTarget'));
    expect(source, contains('g_previewRtv'));
    expect(source, contains('g_previewStaging'));
    expect(source, contains('g_previewRtWidth'));
    expect(source, contains('CreatePreviewRenderTarget'));
    expect(source, contains('g_lastFrameReadbackKind'));

    expect(fullscreenBody, contains('CreateRenderTarget'));
    expect(fullscreenBody, contains('g_rtv'));
    expect(previewBody, contains('CreatePreviewRenderTarget'));
    expect(previewBody, contains('g_previewRtv'));
    expect(previewBody, isNot(contains('CreateRenderTarget(width, height)')));
    expect(previewBody, isNot(contains('g_rtv')));
    expect(overlayBody, contains('CreateRenderTarget'));
    expect(overlayBody, contains('g_rtv'));
    expect(pixelReadbackBody, contains('g_lastFrameReadbackKind'));
    expect(pixelReadbackBody, contains('g_previewRenderTarget'));
    expect(pixelReadbackBody, contains('g_renderTarget'));
  });
}

String _extractFunctionBody(String source, String functionName) {
  var start = -1;
  var openBrace = -1;
  var searchFrom = 0;
  while (true) {
    start = source.indexOf(functionName, searchFrom);
    if (start < 0) {
      fail('Could not find $functionName');
    }
    openBrace = source.indexOf('{', start);
    if (openBrace < 0) {
      fail('Could not find $functionName body');
    }
    final semicolon = source.indexOf(';', start);
    if (semicolon < 0 || openBrace < semicolon) {
      break;
    }
    searchFrom = start + functionName.length;
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
