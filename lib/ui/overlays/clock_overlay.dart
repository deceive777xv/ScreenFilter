import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../models/overlay_component.dart';

/// 可拖拽时钟顶层组件
class ClockOverlay extends StatefulWidget {
  final OverlayComponent component;
  final bool draggable;
  final ValueChanged<Offset> onPositionChanged;

  const ClockOverlay({
    super.key,
    required this.component,
    this.draggable = false,
    required this.onPositionChanged,
  });

  @override
  State<ClockOverlay> createState() => _ClockOverlayState();
}

class _ClockOverlayState extends State<ClockOverlay> {
  late Timer _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  ClockConfig get _config =>
      widget.component.clockConfig ?? const ClockConfig();

  @override
  Widget build(BuildContext context) {
    if (!widget.component.enabled) return const SizedBox.shrink();

    Widget clock = _config.style == ClockStyle.digital
        ? _buildDigitalClock()
        : _buildAnalogClock();

    if (widget.draggable) {
      clock = _wrapDraggable(clock);
    }

    return Positioned(
      left: widget.component.position.dx,
      top: widget.component.position.dy,
      child: clock,
    );
  }

  Widget _wrapDraggable(Widget child) {
    return GestureDetector(
      onPanUpdate: (details) {
        final newPos = widget.component.position + details.delta;
        widget.onPositionChanged(newPos);
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.move,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.blueAccent, width: 1.5),
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.all(4),
          child: child,
        ),
      ),
    );
  }

  Widget _buildDigitalClock() {
    final hour = _config.show24Hour
        ? _now.hour.toString().padLeft(2, '0')
        : ((_now.hour % 12 == 0 ? 12 : _now.hour % 12).toString());
    final minute = _now.minute.toString().padLeft(2, '0');
    final second = _now.second.toString().padLeft(2, '0');
    final amPm = _config.show24Hour ? '' : (_now.hour < 12 ? ' AM' : ' PM');

    final timeText = _config.showSeconds
        ? '$hour:$minute:$second$amPm'
        : '$hour:$minute$amPm';

    return Text(
      timeText,
      style: TextStyle(
        fontSize: _config.fontSize,
        fontWeight: FontWeight.w600,
        color: _config.color,
        fontFamily: 'Consolas',
        shadows: [
          Shadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 4,
            offset: const Offset(1, 1),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalogClock() {
    final size = _config.fontSize * 2.5;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _AnalogClockPainter(
          dateTime: _now,
          color: _config.color,
        ),
      ),
    );
  }
}

class _AnalogClockPainter extends CustomPainter {
  final DateTime dateTime;
  final Color color;

  _AnalogClockPainter({required this.dateTime, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // 表盘外圈
    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, borderPaint);

    // 刻度
    for (int i = 0; i < 12; i++) {
      final angle = (i * 30 - 90) * pi / 180;
      final outer = Offset(
        center.dx + radius * cos(angle),
        center.dy + radius * sin(angle),
      );
      final inner = Offset(
        center.dx + (radius - 8) * cos(angle),
        center.dy + (radius - 8) * sin(angle),
      );
      final tickPaint = Paint()
        ..color = color
        ..strokeWidth = 2;
      canvas.drawLine(inner, outer, tickPaint);
    }

    // 时针
    _drawHand(canvas, center, radius * 0.5,
        (dateTime.hour % 12 + dateTime.minute / 60) * 30 - 90, 3);
    // 分针
    _drawHand(canvas, center, radius * 0.7,
        (dateTime.minute + dateTime.second / 60) * 6 - 90, 2);
    // 秒针
    _drawHand(canvas, center, radius * 0.85, dateTime.second * 6.0 - 90, 1);

    // 中心点
    final dotPaint = Paint()..color = color;
    canvas.drawCircle(center, 3, dotPaint);
  }

  void _drawHand(
      Canvas canvas, Offset center, double length, double angleDeg, double width) {
    final angle = angleDeg * pi / 180;
    final end = Offset(
      center.dx + length * cos(angle),
      center.dy + length * sin(angle),
    );
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, end, paint);
  }

  @override
  bool shouldRepaint(covariant _AnalogClockPainter old) =>
      old.dateTime.second != dateTime.second || old.color != color;
}
