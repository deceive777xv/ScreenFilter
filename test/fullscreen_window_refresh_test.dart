import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_filter_app/services/fullscreen_window_refresh.dart';

void main() {
  test('nudges fullscreen window size and restores it on Windows', () async {
    final binding = _FakeFullscreenWindowBinding(const Size(1920, 1080));

    await refreshFullscreenWindowMetrics(binding: binding, isWindows: true);

    expect(binding.setSizes, [const Size(1921, 1081), const Size(1920, 1080)]);
  });

  test('skips the fullscreen size nudge for invalid window sizes', () async {
    final binding = _FakeFullscreenWindowBinding(Size.zero);

    await refreshFullscreenWindowMetrics(binding: binding, isWindows: true);

    expect(binding.setSizes, isEmpty);
  });
}

class _FakeFullscreenWindowBinding implements FullscreenWindowBinding {
  _FakeFullscreenWindowBinding(this.size);

  final Size size;
  final List<Size> setSizes = [];

  @override
  Future<Size> getSize() async => size;

  @override
  Future<void> setSize(Size size) async {
    setSizes.add(size);
  }
}
