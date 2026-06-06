import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

abstract class FullscreenWindowBinding {
  Future<Size> getSize();
  Future<void> setSize(Size size);
}

class WindowManagerFullscreenWindowBinding implements FullscreenWindowBinding {
  const WindowManagerFullscreenWindowBinding();

  @override
  Future<Size> getSize() => windowManager.getSize();

  @override
  Future<void> setSize(Size size) => windowManager.setSize(size);
}

Future<void> refreshFullscreenWindowMetrics({
  FullscreenWindowBinding binding =
      const WindowManagerFullscreenWindowBinding(),
  bool? isWindows,
}) async {
  if (!(isWindows ?? Platform.isWindows)) return;

  final size = await binding.getSize();
  if (size.width <= 0 || size.height <= 0) return;

  await binding.setSize(Size(size.width + 1, size.height + 1));
  await binding.setSize(size);
}
