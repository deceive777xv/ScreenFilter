import 'package:flutter/material.dart';

import '../widgets/slider_picker.dart';
import '../widgets/slider_title.dart';

int _colorComponent(double value) =>
    (value * 255).round().clamp(0, 255).toInt();

/// Three sliders for selecting a color based on RGB.
class RGBPicker extends StatefulWidget {
  const RGBPicker({required this.color, required this.onChanged, super.key});

  final Color color;
  final ValueChanged<Color> onChanged;

  @override
  State<RGBPicker> createState() => _RGBPickerState();
}

class _RGBPickerState extends State<RGBPicker> {
  Color get color => widget.color;

  // Red
  void redOnChange(double value) => widget.onChanged(
    Color.fromARGB(
      _colorComponent(color.a),
      value.toInt(),
      _colorComponent(color.g),
      _colorComponent(color.b),
    ),
  );
  List<Color> get redColors => <Color>[color.withRed(0), color.withRed(255)];

  // Green
  void greenOnChange(double value) => widget.onChanged(
    Color.fromARGB(
      _colorComponent(color.a),
      _colorComponent(color.r),
      value.toInt(),
      _colorComponent(color.b),
    ),
  );
  List<Color> get greenColors => <Color>[
    color.withGreen(0),
    color.withGreen(255),
  ];

  // Blue
  void blueOnChange(double value) => widget.onChanged(
    Color.fromARGB(
      _colorComponent(color.a),
      _colorComponent(color.r),
      _colorComponent(color.g),
      value.toInt(),
    ),
  );
  List<Color> get blueColors => <Color>[color.withBlue(0), color.withBlue(255)];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Red
        SliderTitle('R', _colorComponent(color.r).toString()),
        SliderPicker(
          value: _colorComponent(color.r).toDouble(),
          max: 255.0,
          onChanged: redOnChange,
          colors: redColors,
        ),

        // Green
        SliderTitle('G', _colorComponent(color.g).toString()),
        SliderPicker(
          value: _colorComponent(color.g).toDouble(),
          max: 255.0,
          onChanged: greenOnChange,
          colors: greenColors,
        ),

        // Blue
        SliderTitle('B', _colorComponent(color.b).toString()),
        SliderPicker(
          value: _colorComponent(color.b).toDouble(),
          max: 255.0,
          onChanged: blueOnChange,
          colors: blueColors,
        ),
      ],
    );
  }
}
