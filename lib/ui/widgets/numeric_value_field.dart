import 'package:flutter/material.dart';

class NumericValueField extends StatefulWidget {
  const NumericValueField({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.fractionDigits = 2,
    this.width = 56,
    this.textStyle,
    this.label,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final int fractionDigits;
  final double width;
  final TextStyle? textStyle;
  final String? label;

  @override
  State<NumericValueField> createState() => _NumericValueFieldState();
}

class _NumericValueFieldState extends State<NumericValueField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  double? _lastCommittedValue;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.value));
    _focusNode = FocusNode()..addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant NumericValueField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_lastCommittedValue == widget.value) {
      _lastCommittedValue = null;
    }
    if (!_focusNode.hasFocus || oldWidget.value != widget.value) {
      _controller.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      _commit();
    }
  }

  void _commit() {
    final text = _controller.text.trim();
    final parsed = double.tryParse(text);
    if (parsed == null) {
      _controller.text = _format(widget.value);
      return;
    }

    final next = parsed.clamp(widget.min, widget.max).toDouble();
    _controller.text = _format(next);
    if (_lastCommittedValue == next || next == widget.value) return;
    _lastCommittedValue = next;
    widget.onChanged(next);
  }

  String _format(double value) => value.toStringAsFixed(widget.fractionDigits);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.label,
      child: SizedBox(
        width: widget.width,
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          textAlign: TextAlign.right,
          style: widget.textStyle,
          maxLines: 1,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _commit(),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 4,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFF3B82F6)),
            ),
          ),
        ),
      ),
    );
  }
}
