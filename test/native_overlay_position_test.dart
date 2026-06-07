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
}

String _extractFunctionBody(String source, String functionName) {
  final start = source.indexOf(functionName);
  if (start < 0) {
    fail('Could not find $functionName');
  }
  final openBrace = source.indexOf('{', start);
  if (openBrace < 0) {
    fail('Could not find $functionName body');
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
