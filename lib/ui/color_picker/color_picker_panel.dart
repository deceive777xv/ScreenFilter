import 'package:flutter/material.dart';
import 'package:flutter_hsvcolor_picker/flutter_hsvcolor_picker.dart'
    as hsv_lib;

import 'pickers/rgb_picker.dart';
import 'pickers/hsv_picker.dart';
import 'pickers/wheel_picker.dart';

/// 取色板类型枚举
enum PickerType {
  rgb,
  hsv,
  wheel,
  paletteHue,
}

/// 自定义颜色选择器面板
/// 从上到下: 预览色+HEX码 → 取色板下拉菜单 → 圆角矩形取色板 → 色带滑块 → 透明度滑块
class ColorPickerPanel extends StatefulWidget {
  const ColorPickerPanel({
    super.key,
    required this.color,
    required this.onChanged,
    this.paletteHeight = 220,
  });

  final Color color;
  final ValueChanged<Color> onChanged;
  final double paletteHeight;

  @override
  State<ColorPickerPanel> createState() => _ColorPickerPanelState();
}

class _ColorPickerPanelState extends State<ColorPickerPanel> {
  late HSVColor _hsvColor;
  late int _alpha;
  late PickerType _pickerType;

  final TextEditingController _hexController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _hsvColor = HSVColor.fromColor(widget.color);
    _alpha = widget.color.alpha;
    _pickerType = PickerType.paletteHue;
    _updateHexText();
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _updateHexText() {
    final c = _hsvColor.toColor();
    final hex = c.red.toRadixString(16).padLeft(2, '0') +
        c.green.toRadixString(16).padLeft(2, '0') +
        c.blue.toRadixString(16).padLeft(2, '0');
    _hexController.text = hex.toUpperCase();
  }

  void _onHSVChanged(HSVColor hsv) {
    setState(() {
      _hsvColor = hsv;
      _updateHexText();
    });
    _emitColor();
  }

  void _onAlphaChanged(double value) {
    setState(() {
      _alpha = value.round();
    });
    _emitColor();
  }

  void _emitColor() {
    final c = _hsvColor.toColor();
    widget.onChanged(Color.fromARGB(_alpha, c.red, c.green, c.blue));
  }

  void _onHexSubmitted(String text) {
    final hex = text.replaceAll('#', '').trim();
    if (hex.length == 6) {
      try {
        final intVal = int.parse(hex, radix: 16);
        final c = Color.fromARGB(255, (intVal >> 16) & 0xFF,
            (intVal >> 8) & 0xFF, intVal & 0xFF);
        setState(() {
          _hsvColor = HSVColor.fromColor(c);
          _updateHexText();
        });
        _emitColor();
      } catch (_) {}
    }
  }

  // ─── 色相条颜色 ───
  static const List<Color> _hueColors = [
    Color.fromARGB(255, 255, 0, 0),
    Color.fromARGB(255, 255, 255, 0),
    Color.fromARGB(255, 0, 255, 0),
    Color.fromARGB(255, 0, 255, 255),
    Color.fromARGB(255, 0, 0, 255),
    Color.fromARGB(255, 255, 0, 255),
    Color.fromARGB(255, 255, 0, 0),
  ];

  // ─── 取色板面的颜色 ───
  List<Color> get _saturationColors => [
        Colors.white,
        HSVColor.fromAHSV(1.0, _hsvColor.hue, 1.0, 1.0).toColor(),
      ];
  static const List<Color> _valueColors = [
    Colors.transparent,
    Colors.black,
  ];

  // Palette Saturation mode colors
  List<Color> get _satModeLR => [
        HSVColor.fromAHSV(1, _hsvColor.hue, 0, 1).toColor(),
        HSVColor.fromAHSV(1, _hsvColor.hue, 1, 1).toColor(),
      ];
  static const List<Color> _satModeTB = [
    Colors.transparent,
    Colors.black,
  ];

  // Palette Value mode colors
  List<Color> get _valModeLR => [
        HSVColor.fromAHSV(1, _hsvColor.hue, 0, 1).toColor(),
        HSVColor.fromAHSV(1, _hsvColor.hue, 1, 1).toColor(),
      ];
  List<Color> get _valModeTB => [
        Colors.white,
        HSVColor.fromAHSV(1, _hsvColor.hue, 0, 0).toColor(),
      ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildPreviewAndHex(),
        const SizedBox(height: 14),
        _buildDropdown(),
        const SizedBox(height: 14),
        _buildBody(),
        const SizedBox(height: 16),
        _buildAlphaSlider(),
      ],
    );
  }

  // ════════════════════════════════════════════
  //  1) 预览色 + HEX 码
  // ════════════════════════════════════════════
  Widget _buildPreviewAndHex() {
    final displayColor = _hsvColor.toColor().withAlpha(_alpha);
    return Row(
      children: [
        // 预览色圆形
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFF3D4055), width: 2),
            boxShadow: const [
              BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2)),
            ],
          ),
          child: ClipOval(
            child: CustomPaint(
              painter: _CheckerPainter(),
              child: Container(color: displayColor),
            ),
          ),
        ),
        const SizedBox(width: 14),
        // HEX 输入
        const Text('#',
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Color(0xFF7C83A1))),
        const SizedBox(width: 4),
        Expanded(
          child: TextField(
            controller: _hexController,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: 3,
                color: Colors.white),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: const Color(0xFF282A3A),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF3D4055)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF3D4055)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: Color(0xFF3B82F6), width: 2),
              ),
              hintText: 'RRGGBB',
              hintStyle: const TextStyle(color: Color(0xFF4A4D60), letterSpacing: 3),
            ),
            onSubmitted: _onHexSubmitted,
          ),
        ),
        const SizedBox(width: 10),
        // Alpha 数值文本
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF282A3A),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF3D4055)),
          ),
          child: Text(
            '${(_alpha / 255 * 100).round()}%',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF60A5FA),
            ),
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════
  //  2) 取色板下拉菜单
  // ════════════════════════════════════════════
  static const _pickerLabels = <PickerType, String>{
    PickerType.rgb: 'RGB',
    PickerType.hsv: 'HSV',
    PickerType.wheel: 'Color Wheel',
    PickerType.paletteHue: 'Palette Hue',
  };

  Widget _buildDropdown() {
    final items = PickerType.values.map((type) {
      return DropdownMenuItem<PickerType>(
        value: type,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            _pickerLabels[type]!,
            style: TextStyle(
              fontSize: 14,
              fontWeight: _pickerType == type ? FontWeight.w600 : FontWeight.w400,
              color: _pickerType == type ? const Color(0xFF60A5FA) : const Color(0xFFB0B5C8),
            ),
          ),
        ),
      );
    }).toList();

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF282A3A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF3D4055)),
      ),
      child: DropdownButton<PickerType>(
        isExpanded: true,
        isDense: false,
        underline: const SizedBox(),
        dropdownColor: const Color(0xFF282A3A),
        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Color(0xFF7C83A1)),
        value: _pickerType,
        items: items,
        onChanged: (v) {
          if (v != null) setState(() => _pickerType = v);
        },
      ),
    );
  }

  // ════════════════════════════════════════════
  //  3) 主体区域 (根据 pickerType 决定内容)
  // ════════════════════════════════════════════
  Widget _buildBody() {
    switch (_pickerType) {
      case PickerType.rgb:
        return RGBPicker(
          color: _hsvColor.toColor(),
          onChanged: (c) => setState(() {
            _hsvColor = HSVColor.fromColor(c);
            _updateHexText();
            _emitColor();
          }),
        );
      case PickerType.hsv:
        return HSVPicker(
          color: _hsvColor,
          onChanged: (hsv) => setState(() {
            _hsvColor = hsv;
            _updateHexText();
            _emitColor();
          }),
        );
      case PickerType.wheel:
        return WheelPicker(
          color: _hsvColor,
          onChanged: (hsv) => setState(() {
            _hsvColor = hsv;
            _updateHexText();
            _emitColor();
          }),
        );
      case PickerType.paletteHue:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildPalette(),
            const SizedBox(height: 16),
            _buildHueSlider(),
          ],
        );
    }
  }

  // ─── 调色板 ───
  Widget _buildPalette() {
    Offset position;
    ValueChanged<Offset> onChanged;
    List<Color> leftRightColors;
    List<Color> topBottomColors;
    double topPos = 0.0, bottomPos = 1.0;

    switch (_pickerType) {
      case PickerType.paletteHue:
        position = Offset(_hsvColor.saturation, _hsvColor.value);
        onChanged = (v) => _onHSVChanged(
            HSVColor.fromAHSV(1, _hsvColor.hue, v.dx, v.dy));
        leftRightColors = _saturationColors;
        topBottomColors = _valueColors;
        topPos = 1.0;
        bottomPos = 0.0;
        break;
      default:
        position = Offset(_hsvColor.saturation, _hsvColor.value);
        onChanged = (v) => _onHSVChanged(
            HSVColor.fromAHSV(1, _hsvColor.hue, v.dx, v.dy));
        leftRightColors = _saturationColors;
        topBottomColors = _valueColors;
        topPos = 1.0;
        bottomPos = 0.0;
        break;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: widget.paletteHeight,
        child: hsv_lib.PalettePicker(
          position: position,
          onChanged: onChanged,
          leftRightColors: leftRightColors,
          topBottomColors: topBottomColors,
          topPosition: topPos,
          bottomPosition: bottomPos,
          border: Border.all(color: const Color(0xFF3D4055), width: 0.5),
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  // ─── 色带滑块 ───
  Widget _buildHueSlider() {
    double value;
    double max;
    List<Color> colors;
    ValueChanged<double> onChanged;
    String label;

    switch (_pickerType) {
      case PickerType.paletteHue:
        value = _hsvColor.hue;
        max = 360.0;
        colors = List.from(_hueColors);
        onChanged = (v) => _onHSVChanged(_hsvColor.withHue(v));
        label = 'Hue';
        break;
      default:
        value = _hsvColor.hue;
        max = 360.0;
        colors = List.from(_hueColors);
        onChanged = (v) => _onHSVChanged(_hsvColor.withHue(v));
        label = 'Hue';
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Row(
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF8B92A5))),
              const Spacer(),
              Text(
                max > 1
                    ? '${value.round()}°'
                    : '${(value * 100).round()}%',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF60A5FA)),
              ),
            ],
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: hsv_lib.SliderPicker(
            value: value,
            max: max,
            onChanged: onChanged,
            colors: colors,
            height: 32,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF3D4055), width: 0.5),
          ),
        ),
      ],
    );
  }

  // ════════════════════════════════════════════
  //  5) 透明度滑块
  // ════════════════════════════════════════════
  Widget _buildAlphaSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Row(
            children: [
              const Text('透明度',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF8B92A5))),
              const Spacer(),
              Text(
                '${(_alpha / 255 * 100).round()}%',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF60A5FA)),
              ),
            ],
          ),
        ),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: hsv_lib.SliderPicker(
            value: _alpha.toDouble(),
            max: 255.0,
            onChanged: _onAlphaChanged,
            height: 32,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF3D4055), width: 0.5),
            child: CustomPaint(
              painter: _AlphaTrackPainter(color: _hsvColor.toColor()),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── 棋盘格背景画笔 (用于透明预览) ───
class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double side = 6;
    final Paint paint = Paint()..color = Colors.black12;
    final Paint white = Paint()..color = Colors.white;
    canvas.drawRect(Offset.zero & size, white);
    for (int y = 0; y * side < size.height; y++) {
      for (int x = 0; x * side < size.width; x++) {
        if ((x + y) % 2 == 0) {
          canvas.drawRect(
              Rect.fromLTWH(x * side, y * side, side, side), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ─── Alpha 条带画笔 ───
class _AlphaTrackPainter extends CustomPainter {
  final Color color;
  _AlphaTrackPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    // 绘制棋盘格
    final double side = size.height / 2;
    final Paint checkPaint = Paint()..color = Colors.black12;
    for (int i = 0; i * side < size.width; i++) {
      if (i % 2 == 0) {
        canvas.drawRect(Rect.fromLTWH(i * side, 0, side, side), checkPaint);
      } else {
        canvas.drawRect(
            Rect.fromLTWH(i * side, side, side, side), checkPaint);
      }
    }

    // 绘制渐变
    final rect = Offset.zero & size;
    final gradient = LinearGradient(
      colors: [color.withAlpha(0), color.withAlpha(255)],
    );
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
  }

  @override
  bool shouldRepaint(_AlphaTrackPainter old) => old.color != color;
}
