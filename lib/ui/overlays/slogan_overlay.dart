import 'package:flutter/material.dart';
import '../../models/overlay_component.dart';

/// 可拖拽标语顶层组件
class SloganOverlay extends StatelessWidget {
  final OverlayComponent component;
  final bool draggable;
  final ValueChanged<Offset> onPositionChanged;

  const SloganOverlay({
    super.key,
    required this.component,
    this.draggable = false,
    required this.onPositionChanged,
  });

  SloganConfig get _config =>
      component.sloganConfig ?? const SloganConfig();

  @override
  Widget build(BuildContext context) {
    if (!component.enabled || _config.text.isEmpty) {
      return const SizedBox.shrink();
    }

    Widget slogan = Text(
      _config.text,
      style: TextStyle(
        fontSize: _config.fontSize,
        fontWeight: _config.fontWeight,
        color: _config.color,
        fontFamily: _config.fontFamily,
        shadows: [
          Shadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 4,
            offset: const Offset(1, 1),
          ),
        ],
      ),
    );

    if (draggable) {
      slogan = GestureDetector(
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
            child: slogan,
          ),
        ),
      );
    }

    return Positioned(
      left: component.position.dx,
      top: component.position.dy,
      child: slogan,
    );
  }
}
