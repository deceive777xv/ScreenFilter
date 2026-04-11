import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/win32_helpers.dart';

/// 专注模式覆盖层 — 除当前活动窗口外，其余区域变暗。
class FocusModeOverlay extends StatefulWidget {
  final bool enabled;
  final double dimOpacity;
  final double borderRadius;
  final double devicePixelRatio;

  const FocusModeOverlay({
    super.key,
    required this.enabled,
    this.dimOpacity = 0.5,
    this.borderRadius = 8.0,
    this.devicePixelRatio = 1.0,
  });

  @override
  State<FocusModeOverlay> createState() => _FocusModeOverlayState();
}

class _FocusModeOverlayState extends State<FocusModeOverlay> {
  Timer? _timer;
  Rect? _windowRect;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _startTracking();
  }

  @override
  void didUpdateWidget(FocusModeOverlay old) {
    super.didUpdateWidget(old);
    if (widget.enabled && !old.enabled) {
      _startTracking();
    } else if (!widget.enabled && old.enabled) {
      _stopTracking();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTracking() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      final rect = getForegroundWindowRect();
      if (rect != _windowRect) {
        setState(() => _windowRect = rect);
      }
    });
  }

  void _stopTracking() {
    _timer?.cancel();
    _timer = null;
    _windowRect = null;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();
    return CustomPaint(
      size: Size.infinite,
      painter: _FocusModePainter(
        windowRect: _windowRect,
        dimOpacity: widget.dimOpacity,
        borderRadius: widget.borderRadius,
        dpr: widget.devicePixelRatio,
      ),
    );
  }
}

class _FocusModePainter extends CustomPainter {
  final Rect? windowRect;
  final double dimOpacity;
  final double borderRadius;
  final double dpr;

  _FocusModePainter({
    this.windowRect,
    this.dimOpacity = 0.5,
    this.borderRadius = 8.0,
    this.dpr = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fullRect = Offset.zero & size;
    final paint = Paint()..color = Color.fromRGBO(0, 0, 0, dimOpacity);

    if (windowRect != null) {
      // Convert physical coords to logical coords.
      final logicalRect = Rect.fromLTRB(
        windowRect!.left / dpr,
        windowRect!.top / dpr,
        windowRect!.right / dpr,
        windowRect!.bottom / dpr,
      );

      final fullPath = Path()..addRect(fullRect);
      final windowPath = Path()
        ..addRRect(RRect.fromRectAndRadius(
          logicalRect.intersect(fullRect),
          Radius.circular(borderRadius),
        ));
      final combined =
          Path.combine(PathOperation.difference, fullPath, windowPath);
      canvas.drawPath(combined, paint);
    } else {
      canvas.drawRect(fullRect, paint);
    }
  }

  @override
  bool shouldRepaint(_FocusModePainter old) =>
      old.windowRect != windowRect ||
      old.dimOpacity != dimOpacity ||
      old.borderRadius != borderRadius;
}
