import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;

/// 屏幕导航图 — 缩略图上拖拽定位组件位置
class ScreenPositionPicker extends StatefulWidget {
  final Offset position;
  final ValueChanged<Offset> onPositionChanged;
  final String label;
  final Size componentSize;

  const ScreenPositionPicker({
    super.key,
    required this.position,
    required this.onPositionChanged,
    this.label = '',
    this.componentSize = const Size(200, 80),
  });

  @override
  State<ScreenPositionPicker> createState() => _ScreenPositionPickerState();
}

class _ScreenPositionPickerState extends State<ScreenPositionPicker> {
  static const double _mapWidth = 260;
  static const double _dotRadius = 6;
  static const double _margin = 16;

  final Set<_Direction> _activeDirections = {};

  /// 设备像素比
  double get _dpr =>
      ui.PlatformDispatcher.instance.views.first.devicePixelRatio;

  /// 逻辑屏幕尺寸（与 Positioned 坐标一致）
  Size get _screenSize {
    final view = ui.PlatformDispatcher.instance.views.first;
    return view.physicalSize / view.devicePixelRatio;
  }

  /// 物理分辨率（用于界面显示和坐标换算）
  Size get _physicalScreenSize =>
      ui.PlatformDispatcher.instance.views.first.physicalSize;

  double get _mapHeight {
    final ss = _screenSize;
    if (ss.width == 0) return 160;
    return _mapWidth * ss.height / ss.width;
  }

  double get _scaleX => _mapWidth / _screenSize.width;
  double get _scaleY => _mapHeight / _screenSize.height;

  Size get _cSize => widget.componentSize;

  double get _maxRealX =>
      (_screenSize.width - _cSize.width).clamp(0.0, double.infinity);
  double get _maxRealY =>
      (_screenSize.height - _cSize.height).clamp(0.0, double.infinity);

  // ── 拖拽 / 点击 ─────────────────────────────────────

  void _onTapOrDrag(Offset localPos) {
    // 点击位置代表组件中心
    final centerX = localPos.dx / _scaleX;
    final centerY = localPos.dy / _scaleY;
    final realX = (centerX - _cSize.width / 2).clamp(0.0, _maxRealX);
    final realY = (centerY - _cSize.height / 2).clamp(0.0, _maxRealY);
    widget.onPositionChanged(Offset(realX, realY));
    setState(() => _activeDirections.clear());
  }

  // ── 方向按钮组合逻辑 ──────────────────────────────────

  void _toggleDirection(_Direction dir) {
    setState(() {
      if (dir == _Direction.center) {
        _activeDirections.clear();
        widget.onPositionChanged(Offset(
          (_maxRealX / 2).clamp(0, _maxRealX),
          (_maxRealY / 2).clamp(0, _maxRealY),
        ));
        return;
      }

      // 移除相反方向
      final opposite = _oppositeOf(dir);
      if (opposite != null) _activeDirections.remove(opposite);

      // 切换当前方向
      if (_activeDirections.contains(dir)) {
        _activeDirections.remove(dir);
      } else {
        _activeDirections.add(dir);
      }

      _applyDirectionPreset();
    });
  }

  _Direction? _oppositeOf(_Direction dir) => switch (dir) {
        _Direction.left => _Direction.right,
        _Direction.right => _Direction.left,
        _Direction.top => _Direction.bottom,
        _Direction.bottom => _Direction.top,
        _ => null,
      };

  void _applyDirectionPreset() {
    double x, y;

    if (_activeDirections.contains(_Direction.left)) {
      x = _margin.clamp(0.0, _maxRealX);
    } else if (_activeDirections.contains(_Direction.right)) {
      x = (_maxRealX - _margin).clamp(0.0, _maxRealX);
    } else {
      x = (_maxRealX / 2).clamp(0.0, _maxRealX);
    }

    if (_activeDirections.contains(_Direction.top)) {
      y = _margin.clamp(0.0, _maxRealY);
    } else if (_activeDirections.contains(_Direction.bottom)) {
      y = (_maxRealY - _margin).clamp(0.0, _maxRealY);
    } else {
      y = (_maxRealY / 2).clamp(0.0, _maxRealY);
    }

    widget.onPositionChanged(Offset(x, y));
  }

  // ── 坐标输入对话框 ──────────────────────────────────

  void _showCoordinateInput() {
    // 显示/输入组件中心的物理像素坐标
    final centerPhysX = ((widget.position.dx + _cSize.width / 2) * _dpr).round();
    final centerPhysY = ((widget.position.dy + _cSize.height / 2) * _dpr).round();
    final xCtrl = TextEditingController(text: '$centerPhysX');
    final yCtrl = TextEditingController(text: '$centerPhysY');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('输入坐标',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: xCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                    labelText: 'X',
                    isDense: true,
                    border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: yCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                    labelText: 'Y',
                    isDense: true,
                    border: OutlineInputBorder()),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child:
                  const Text('取消', style: TextStyle(color: Colors.black54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white),
            onPressed: () {
              // 用户输入的是组件中心物理坐标，转换为左上角逻辑坐标
              final px = double.tryParse(xCtrl.text) ?? 0;
              final py = double.tryParse(yCtrl.text) ?? 0;
              final x = (px / _dpr - _cSize.width / 2).clamp(0.0, _maxRealX);
              final y = (py / _dpr - _cSize.height / 2).clamp(0.0, _maxRealY);
              widget.onPositionChanged(Offset(x, y));
              Navigator.pop(ctx);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  // ── build ──────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // 游标位置：表示组件中心在导览图上的位置
    final compCenterX = widget.position.dx + _cSize.width / 2;
    final compCenterY = widget.position.dy + _cSize.height / 2;
    final dotX =
        (compCenterX * _scaleX).clamp(_dotRadius, _mapWidth - _dotRadius);
    final dotY =
        (compCenterY * _scaleY).clamp(_dotRadius, _mapHeight - _dotRadius);

    // 组件矩形在导览图上的位置
    final compMapX = widget.position.dx * _scaleX;
    final compMapY = widget.position.dy * _scaleY;
    final compMapW = _cSize.width * _scaleX;
    final compMapH = _cSize.height * _scaleY;

    final physSize = _physicalScreenSize;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // 分辨率标签
        Text(
          '屏幕分辨率: ${physSize.width.round()} × ${physSize.height.round()}',
          style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 4),
        // 顶部一行：快捷按钮 + 坐标显示
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _dirBtn(Icons.arrow_upward, '上', _Direction.top),
            const SizedBox(width: 3),
            _dirBtn(Icons.arrow_downward, '下', _Direction.bottom),
            const SizedBox(width: 3),
            _dirBtn(Icons.arrow_back, '左', _Direction.left),
            const SizedBox(width: 3),
            _dirBtn(Icons.arrow_forward, '右', _Direction.right),
            const SizedBox(width: 3),
            _dirBtn(Icons.center_focus_strong, '中', _Direction.center),
            const SizedBox(width: 8),
            // 坐标可点击编辑
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _showCoordinateInput,
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F0F0),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.edit_location_alt,
                          size: 13, color: Colors.blueAccent),
                      const SizedBox(width: 4),
                      Text(
                        '(${((widget.position.dx + _cSize.width / 2) * _dpr).round()}, ${((widget.position.dy + _cSize.height / 2) * _dpr).round()})',
                        style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                            fontFamily: 'Consolas'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // 导览图（居中）
        GestureDetector(
          onTapDown: (d) => _onTapOrDrag(d.localPosition),
          onPanUpdate: (d) => _onTapOrDrag(d.localPosition),
          child: Container(
            width: _mapWidth,
            height: _mapHeight,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade400),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: CustomPaint(
                painter: _ScreenMapPainter(
                  dotX: dotX,
                  dotY: dotY,
                  dotRadius: _dotRadius,
                  label: widget.label,
                  compRect: Rect.fromLTWH(
                      compMapX, compMapY, compMapW, compMapH),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dirBtn(IconData icon, String tooltip, _Direction dir) {
    final isActive = _activeDirections.contains(dir);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _toggleDirection(dir),
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: isActive ? Colors.blueAccent : const Color(0xFFF0F0F0),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: isActive ? Colors.blueAccent : Colors.black12),
            ),
            child: Icon(icon,
                size: 15, color: isActive ? Colors.white : Colors.black54),
          ),
        ),
      ),
    );
  }
}

enum _Direction { left, right, top, bottom, center }

class _ScreenMapPainter extends CustomPainter {
  final double dotX;
  final double dotY;
  final double dotRadius;
  final String label;
  final Rect compRect;

  _ScreenMapPainter({
    required this.dotX,
    required this.dotY,
    required this.dotRadius,
    required this.label,
    required this.compRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 网格线
    final gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..strokeWidth = 0.5;
    for (double x = 0; x < size.width; x += size.width / 8) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y < size.height; y += size.height / 5) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // 组件矩形预览
    final compFillPaint = Paint()
      ..color = Colors.blueAccent.withOpacity(0.15)
      ..style = PaintingStyle.fill;
    canvas.drawRect(compRect, compFillPaint);
    final compStrokePaint = Paint()
      ..color = Colors.blueAccent.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawRect(compRect, compStrokePaint);

    // 十字线
    final crossPaint = Paint()
      ..color = Colors.blueAccent.withOpacity(0.4)
      ..strokeWidth = 0.8;
    canvas.drawLine(Offset(dotX, 0), Offset(dotX, size.height), crossPaint);
    canvas.drawLine(Offset(0, dotY), Offset(size.width, dotY), crossPaint);

    // 定位点外圈
    final outerPaint = Paint()
      ..color = Colors.blueAccent.withOpacity(0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(dotX, dotY), dotRadius + 4, outerPaint);

    // 定位点
    final dotPaint = Paint()
      ..color = Colors.blueAccent
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(dotX, dotY), dotRadius, dotPaint);

    // 定位点白色内圈
    final innerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(dotX, dotY), 3, innerPaint);

    // 标签
    if (label.isNotEmpty) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.7),
            fontSize: 10,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelX = (dotX + 14).clamp(0.0, size.width - textPainter.width);
      final labelY = (dotY - 6).clamp(0.0, size.height - textPainter.height);
      textPainter.paint(canvas, Offset(labelX, labelY));
    }
  }

  @override
  bool shouldRepaint(covariant _ScreenMapPainter old) =>
      old.dotX != dotX || old.dotY != dotY || old.compRect != compRect;
}
