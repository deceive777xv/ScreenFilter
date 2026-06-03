import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../services/win32_polling_service.dart';

/// 聚光灯覆盖层 — 鼠标周围亮圈，其余区域变暗。
class SpotlightOverlay extends StatefulWidget {
  final bool enabled;
  final double radius;
  final double dimOpacity;
  final double softEdge;
  final double devicePixelRatio;
  final Win32PollingService win32PollingService;

  const SpotlightOverlay({
    super.key,
    required this.enabled,
    required this.win32PollingService,
    this.radius = 200.0,
    this.dimOpacity = 0.6,
    this.softEdge = 50.0,
    this.devicePixelRatio = 1.0,
  });

  @override
  State<SpotlightOverlay> createState() => _SpotlightOverlayState();
}

class _SpotlightOverlayState extends State<SpotlightOverlay> {
  Win32PollingRelease? _pollingRelease;
  Offset _mousePos = Offset.zero;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _startTracking();
  }

  @override
  void didUpdateWidget(SpotlightOverlay old) {
    super.didUpdateWidget(old);
    if (widget.enabled &&
        (!old.enabled ||
            old.win32PollingService != widget.win32PollingService)) {
      _startTracking();
    } else if (!widget.enabled && old.enabled) {
      _stopTracking();
    }
  }

  @override
  void dispose() {
    _pollingRelease?.call();
    super.dispose();
  }

  void _startTracking() {
    _pollingRelease?.call();
    _pollingRelease = widget.win32PollingService.addCursorPositionListener(
      _onCursorPositionChanged,
    );
    _onCursorPositionChanged();
  }

  void _stopTracking() {
    _pollingRelease?.call();
    _pollingRelease = null;
  }

  void _onCursorPositionChanged() {
    final pos = widget.win32PollingService.cursorPosition.value;
    if (!mounted || pos == _mousePos) return;
    setState(() => _mousePos = pos);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();
    return CustomPaint(
      size: Size.infinite,
      painter: _SpotlightPainter(
        mousePos: _mousePos,
        radius: widget.radius,
        dimOpacity: widget.dimOpacity,
        softEdge: widget.softEdge,
        dpr: widget.devicePixelRatio,
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Offset mousePos;
  final double radius;
  final double dimOpacity;
  final double softEdge;
  final double dpr;

  _SpotlightPainter({
    required this.mousePos,
    this.radius = 200.0,
    this.dimOpacity = 0.6,
    this.softEdge = 50.0,
    this.dpr = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fullRect = Offset.zero & size;

    // Convert physical mouse coords to logical.
    final logicalMouse = Offset(mousePos.dx / dpr, mousePos.dy / dpr);

    // Use saveLayer + BlendMode.dstOut to create smooth spotlight.
    canvas.saveLayer(fullRect, Paint());

    // Fill with dim color.
    canvas.drawRect(
      fullRect,
      Paint()..color = Color.fromRGBO(0, 0, 0, dimOpacity),
    );

    // Erase the spotlight area using a radial gradient for soft edge.
    final innerRadius = radius;
    final outerRadius = radius + softEdge;
    final spotPaint = Paint()
      ..blendMode = BlendMode.dstOut
      ..shader = ui.Gradient.radial(
        logicalMouse,
        outerRadius,
        [
          const Color(0xFFFFFFFF),
          const Color(0xFFFFFFFF),
          const Color(0x00FFFFFF),
        ],
        [0.0, innerRadius / outerRadius, 1.0],
      );
    canvas.drawCircle(logicalMouse, outerRadius, spotPaint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) =>
      old.mousePos != mousePos ||
      old.radius != radius ||
      old.dimOpacity != dimOpacity ||
      old.softEdge != softEdge;
}
