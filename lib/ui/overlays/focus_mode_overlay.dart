import 'package:flutter/material.dart';
import '../../services/win32_polling_service.dart';

/// 专注模式覆盖层 — 除当前活动窗口外，其余区域变暗。
class FocusModeOverlay extends StatefulWidget {
  final bool enabled;
  final double dimOpacity;
  final double borderRadius;
  final double devicePixelRatio;
  final Win32PollingService win32PollingService;

  const FocusModeOverlay({
    super.key,
    required this.enabled,
    required this.win32PollingService,
    this.dimOpacity = 0.5,
    this.borderRadius = 8.0,
    this.devicePixelRatio = 1.0,
  });

  @override
  State<FocusModeOverlay> createState() => _FocusModeOverlayState();
}

class _FocusModeOverlayState extends State<FocusModeOverlay> {
  Win32PollingRelease? _pollingRelease;
  Rect? _windowRect;

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _startTracking();
  }

  @override
  void didUpdateWidget(FocusModeOverlay old) {
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
    _pollingRelease = widget.win32PollingService
        .addForegroundWindowRectListener(_onForegroundWindowRectChanged);
    _onForegroundWindowRectChanged();
  }

  void _stopTracking() {
    _pollingRelease?.call();
    _pollingRelease = null;
    _windowRect = null;
  }

  void _onForegroundWindowRectChanged() {
    final rect = widget.win32PollingService.foregroundWindowRect.value;
    if (!mounted || rect == _windowRect) return;
    setState(() => _windowRect = rect);
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
        ..addRRect(
          RRect.fromRectAndRadius(
            logicalRect.intersect(fullRect),
            Radius.circular(borderRadius),
          ),
        );
      final combined = Path.combine(
        PathOperation.difference,
        fullPath,
        windowPath,
      );
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
