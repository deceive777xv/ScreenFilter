import 'package:flutter/material.dart';

/// 全屏覆盖层，让用户点击放置多边形顶点来绘制遮罩区域。
class RegionMaskDrawingOverlay extends StatefulWidget {
  final List<Offset>? existingVertices;
  final void Function(List<Offset> polygon) onComplete;
  final VoidCallback onCancel;

  const RegionMaskDrawingOverlay({
    super.key,
    this.existingVertices,
    required this.onComplete,
    required this.onCancel,
  });

  @override
  State<RegionMaskDrawingOverlay> createState() => _RegionMaskDrawingOverlayState();
}

class _RegionMaskDrawingOverlayState extends State<RegionMaskDrawingOverlay> {
  late List<Offset> _vertices;
  int? _draggingIndex;
  Offset? _cursorPos;

  @override
  void initState() {
    super.initState();
    _vertices = widget.existingVertices != null
        ? List<Offset>.from(widget.existingVertices!)
        : [];
  }

  void _addVertex(Offset pos) {
    setState(() => _vertices.add(pos));
  }

  void _undoLast() {
    if (_vertices.isNotEmpty) {
      setState(() => _vertices.removeLast());
    }
  }

  void _finish() {
    if (_vertices.length >= 3) {
      widget.onComplete(_vertices);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (e) => setState(() => _cursorPos = e.localPosition),
      child: GestureDetector(
        onTapUp: (details) {
          if (_draggingIndex != null) return;
          // 检查是否点击了已有顶点（编辑模式拖拽）
          final hitIndex = _hitTestVertex(details.localPosition);
          if (hitIndex == null) {
            _addVertex(details.localPosition);
          }
        },
        onPanStart: (details) {
          final hitIndex = _hitTestVertex(details.localPosition);
          if (hitIndex != null) {
            setState(() => _draggingIndex = hitIndex);
          }
        },
        onPanUpdate: (details) {
          if (_draggingIndex != null) {
            setState(() => _vertices[_draggingIndex!] = details.localPosition);
          }
        },
        onPanEnd: (_) {
          setState(() => _draggingIndex = null);
        },
        child: Stack(
          children: [
            // 半透明遮罩背景
            Container(color: const Color(0x40000000)),
            // 绘制多边形
            CustomPaint(
              size: Size.infinite,
              painter: _PolygonDrawingPainter(
                vertices: _vertices,
                cursorPos: _cursorPos,
              ),
            ),
            // 指引文本
            Positioned(
              top: 40,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xDD1E2030),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _vertices.isEmpty
                        ? '点击屏幕放置多边形顶点'
                        : '已放置 ${_vertices.length} 个顶点，至少需要 3 个  |  拖拽顶点可调整位置',
                    style: const TextStyle(color: Colors.white, fontSize: 14, decoration: TextDecoration.none),
                  ),
                ),
              ),
            ),
            // 浮动工具栏
            Positioned(
              bottom: 60,
              left: 0,
              right: 0,
              child: Center(child: _buildToolbar()),
            ),
          ],
        ),
      ),
    );
  }

  int? _hitTestVertex(Offset pos) {
    const hitRadius = 14.0;
    for (int i = 0; i < _vertices.length; i++) {
      if ((pos - _vertices[i]).distance <= hitRadius) return i;
    }
    return null;
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xDD1E2030),
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Color(0x30000000), blurRadius: 16, offset: Offset(0, 4))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toolBtn(Icons.undo_rounded, '撤销', _vertices.isEmpty ? null : _undoLast),
          const SizedBox(width: 12),
          _toolBtn(Icons.check_circle_rounded, '完成', _vertices.length >= 3 ? _finish : null,
              highlight: true),
          const SizedBox(width: 12),
          _toolBtn(Icons.cancel_rounded, '取消', widget.onCancel),
        ],
      ),
    );
  }

  Widget _toolBtn(IconData icon, String label, VoidCallback? onTap, {bool highlight = false}) {
    final active = onTap != null;
    final color = !active
        ? const Color(0xFF6B7280)
        : highlight
            ? const Color(0xFF3B82F6)
            : Colors.white;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: highlight && active ? const Color(0x203B82F6) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600, decoration: TextDecoration.none)),
          ],
        ),
      ),
    );
  }
}

class _PolygonDrawingPainter extends CustomPainter {
  final List<Offset> vertices;
  final Offset? cursorPos;

  _PolygonDrawingPainter({required this.vertices, this.cursorPos});

  @override
  void paint(Canvas canvas, Size size) {
    if (vertices.isEmpty) return;

    final fillPaint = Paint()
      ..color = const Color(0x303B82F6)
      ..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..color = const Color(0xFF3B82F6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    final vertexPaint = Paint()
      ..color = const Color(0xFF3B82F6)
      ..style = PaintingStyle.fill;
    final vertexBorderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    final dashPaint = Paint()
      ..color = const Color(0x803B82F6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    // 绘制已闭合的多边形填充
    if (vertices.length >= 3) {
      final path = Path()..addPolygon(vertices, true);
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, strokePaint);
    } else if (vertices.length == 2) {
      canvas.drawLine(vertices[0], vertices[1], strokePaint);
    }

    // 从最后一个顶点到光标的虚线
    if (cursorPos != null && vertices.isNotEmpty) {
      canvas.drawLine(vertices.last, cursorPos!, dashPaint);
      if (vertices.length >= 2) {
        // 也从光标画回第一个顶点（预览闭合效果）
        canvas.drawLine(cursorPos!, vertices.first, dashPaint);
      }
    }

    // 绘制顶点圆点
    for (int i = 0; i < vertices.length; i++) {
      canvas.drawCircle(vertices[i], 6, vertexPaint);
      canvas.drawCircle(vertices[i], 6, vertexBorderPaint);
      // 第一个顶点画一个额外的外圈标识
      if (i == 0) {
        final firstPaint = Paint()
          ..color = const Color(0x403B82F6)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(vertices[i], 12, firstPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PolygonDrawingPainter oldDelegate) => true;
}
