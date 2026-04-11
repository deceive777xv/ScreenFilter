import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/overlay_component.dart';

/// 可拖拽水印图顶层组件
class WatermarkOverlay extends StatelessWidget {
  final OverlayComponent component;
  final bool draggable;
  final ValueChanged<Offset> onPositionChanged;

  const WatermarkOverlay({
    super.key,
    required this.component,
    this.draggable = false,
    required this.onPositionChanged,
  });

  WatermarkConfig get _config =>
      component.watermarkConfig ?? const WatermarkConfig();

  @override
  Widget build(BuildContext context) {
    if (!component.enabled || _config.imagePath.isEmpty) {
      return const SizedBox.shrink();
    }

    final file = File(_config.imagePath);
    if (!file.existsSync()) return const SizedBox.shrink();

    Widget watermark = Opacity(
      opacity: _config.opacity,
      child: Image.file(
        file,
        width: _config.width,
        height: _config.height,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    );

    if (draggable) {
      watermark = GestureDetector(
        onPanUpdate: (details) {
          final newPos = component.position + details.delta;
          onPositionChanged(newPos);
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.move,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.blueAccent, width: 1.5),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(4),
            child: watermark,
          ),
        ),
      );
    }

    return Positioned(
      left: component.position.dx,
      top: component.position.dy,
      child: watermark,
    );
  }
}
