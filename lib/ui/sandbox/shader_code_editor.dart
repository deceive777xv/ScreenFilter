import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A code editor widget with HLSL/GLSL syntax highlighting, line numbers,
/// and a dark theme designed for the Shader Sandbox.
class ShaderCodeEditor extends StatefulWidget {
  final String initialCode;
  final ValueChanged<String> onCodeChanged;
  final String? errorMessage;

  const ShaderCodeEditor({
    super.key,
    required this.initialCode,
    required this.onCodeChanged,
    this.errorMessage,
  });

  @override
  State<ShaderCodeEditor> createState() => ShaderCodeEditorState();
}

class ShaderCodeEditorState extends State<ShaderCodeEditor> {
  late _HighlightController _controller;
  late ScrollController _scrollController;
  late FocusNode _focusNode;
  int _lineCount = 1;

  final ScrollController _lineNumberScrollController = ScrollController();

  static const double _lineHeight = 20.0;
  static const double _fontSize = 13.0;
  static const String _fontFamily = 'Consolas';

  @override
  void initState() {
    super.initState();
    _controller = _HighlightController(text: widget.initialCode);
    _scrollController = ScrollController();
    _focusNode = FocusNode();
    _lineCount = '\n'.allMatches(widget.initialCode).length + 1;

    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final newCount = '\n'.allMatches(_controller.text).length + 1;
    if (newCount != _lineCount) {
      setState(() => _lineCount = newCount);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _scrollController.dispose();
    _lineNumberScrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void setCode(String code) {
    _controller.text = code;
    setState(() {
      _lineCount = '\n'.allMatches(code).length + 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E2E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: widget.errorMessage != null && widget.errorMessage!.isNotEmpty
                    ? const Color(0xFFEF4444)
                    : const Color(0xFF313244),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildLineNumbers(),
                  Expanded(child: _buildCodeArea()),
                ],
              ),
            ),
          ),
        ),
        if (widget.errorMessage != null && widget.errorMessage!.isNotEmpty)
          _buildErrorPanel(),
      ],
    );
  }

  Widget _buildLineNumbers() {
    return Container(
      width: 48,
      color: const Color(0xFF181825),
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: ListView.builder(
          controller: _lineNumberScrollController,
          itemCount: _lineCount,
          itemExtent: _lineHeight,
          physics: const NeverScrollableScrollPhysics(),
          itemBuilder: (context, index) {
            return Container(
              height: _lineHeight,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  fontFamily: _fontFamily,
                  fontSize: _fontSize,
                  color: Colors.white.withValues(alpha: 0.25),
                  height: _lineHeight / _fontSize,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildCodeArea() {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (_lineNumberScrollController.hasClients) {
          _lineNumberScrollController.jumpTo(notification.metrics.pixels);
        }
        return false;
      },
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        maxLines: null,
        scrollController: _scrollController,
        style: TextStyle(
          fontFamily: _fontFamily,
          fontSize: _fontSize,
          color: const Color(0xFFCDD6F4),
          height: _lineHeight / _fontSize,
        ),
        cursorColor: const Color(0xFF89B4FA),
        cursorWidth: 2,
        decoration: const InputDecoration(
          contentPadding: EdgeInsets.all(12),
          border: InputBorder.none,
          isCollapsed: true,
        ),
        inputFormatters: [
          _TabInputFormatter(),
        ],
        onChanged: (text) {
          widget.onCodeChanged(text);
        },
      ),
    );
  }

  Widget _buildErrorPanel() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF2D1B1B),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF7F1D1D)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.errorMessage!,
              style: const TextStyle(
                fontFamily: _fontFamily,
                fontSize: 12,
                color: Color(0xFFFCA5A5),
                height: 1.4,
              ),
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Syntax-highlighting TextEditingController ───────────────────────────────
// Overrides buildTextSpan so the TextField itself renders colored text.
// This keeps cursor, selection, and scrolling perfectly aligned.

class _HighlightController extends TextEditingController {
  _HighlightController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final children = _highlightHLSL(text);
    return TextSpan(style: style, children: children);
  }

  static final _keywordPattern = RegExp(
    r'\b(?:if|else|for|while|do|switch|case|default|break|continue|return|discard|struct|cbuffer|register|typedef)\b'
  );
  static final _typePattern = RegExp(
    r'\b(?:void|bool|int|uint|float|double|half|'
    r'float[1-4]|float[1-4]x[1-4]|int[1-4]|uint[1-4]|bool[1-4]|half[1-4]|'
    r'sampler|sampler2D|SamplerState|Texture2D|Texture3D|TextureCube|'
    r'RWTexture2D|StructuredBuffer|RWStructuredBuffer)\b'
  );
  static final _semanticPattern = RegExp(
    r'\b(?:SV_POSITION|SV_TARGET[0-7]?|SV_VertexID|SV_InstanceID|SV_DispatchThreadID|'
    r'TEXCOORD[0-9]?|COLOR[0-9]?|NORMAL|TANGENT|BINORMAL|POSITION[0-9]?)\b'
  );
  static final _builtinFuncPattern = RegExp(
    r'\b(?:sin|cos|tan|asin|acos|atan|atan2|'
    r'abs|ceil|floor|round|frac|fmod|modf|'
    r'sqrt|rsqrt|pow|exp|exp2|log|log2|log10|'
    r'min|max|clamp|saturate|lerp|step|smoothstep|'
    r'length|distance|dot|cross|normalize|reflect|refract|'
    r'mul|transpose|determinant|'
    r'tex2D|tex2Dlod|tex2Dgrad|Sample|SampleLevel|Load|'
    r'ddx|ddy|fwidth|sign|trunc|rcp|'
    r'all|any|clip|lit|noise)\b'
  );
  static final _numberPattern = RegExp(
    r'\b(?:0[xX][0-9a-fA-F]+|[0-9]*\.?[0-9]+(?:[eE][+-]?[0-9]+)?[fFhHuUlL]?)\b'
  );
  static final _uniformPattern = RegExp(
    r'\bu_(?:Time|Resolution|Mouse|AccentColor)\b'
  );

  static const _colorKeyword  = Color(0xFFCBA6F7);
  static const _colorType     = Color(0xFF89B4FA);
  static const _colorSemantic = Color(0xFFF9E2AF);
  static const _colorBuiltin  = Color(0xFF94E2D5);
  static const _colorNumber   = Color(0xFFFAB387);
  static const _colorString   = Color(0xFFA6E3A1);
  static const _colorComment  = Color(0xFF6C7086);
  static const _colorUniform  = Color(0xFFF38BA8);

  static List<TextSpan> _highlightHLSL(String code) {
    final List<TextSpan> spans = [];
    int i = 0;

    while (i < code.length) {
      // Line comment
      if (i + 1 < code.length && code[i] == '/' && code[i + 1] == '/') {
        int end = code.indexOf('\n', i);
        if (end == -1) end = code.length;
        spans.add(TextSpan(text: code.substring(i, end), style: const TextStyle(color: _colorComment)));
        i = end;
        continue;
      }

      // Block comment
      if (i + 1 < code.length && code[i] == '/' && code[i + 1] == '*') {
        int end = code.indexOf('*/', i + 2);
        if (end == -1) end = code.length; else end += 2;
        spans.add(TextSpan(text: code.substring(i, end), style: const TextStyle(color: _colorComment)));
        i = end;
        continue;
      }

      // String literal
      if (code[i] == '"') {
        int end = i + 1;
        while (end < code.length && code[end] != '"') {
          if (code[end] == '\\') end++;
          end++;
        }
        if (end < code.length) end++;
        spans.add(TextSpan(text: code.substring(i, end), style: const TextStyle(color: _colorString)));
        i = end;
        continue;
      }

      // Word token
      if (_isWordChar(code[i])) {
        int end = i;
        while (end < code.length && _isWordCharOrDot(code[end])) end++;
        final word = code.substring(i, end);

        if (_uniformPattern.hasMatch(word)) {
          spans.add(TextSpan(text: word, style: const TextStyle(color: _colorUniform, fontWeight: FontWeight.w600)));
        } else if (_keywordPattern.hasMatch(word)) {
          spans.add(TextSpan(text: word, style: const TextStyle(color: _colorKeyword, fontWeight: FontWeight.w600)));
        } else if (_typePattern.hasMatch(word)) {
          spans.add(TextSpan(text: word, style: const TextStyle(color: _colorType)));
        } else if (_semanticPattern.hasMatch(word)) {
          spans.add(TextSpan(text: word, style: const TextStyle(color: _colorSemantic)));
        } else if (_builtinFuncPattern.hasMatch(word)) {
          spans.add(TextSpan(text: word, style: const TextStyle(color: _colorBuiltin)));
        } else if (_numberPattern.hasMatch(word)) {
          spans.add(TextSpan(text: word, style: const TextStyle(color: _colorNumber)));
        } else {
          spans.add(TextSpan(text: word));
        }
        i = end;
        continue;
      }

      // Other characters
      spans.add(TextSpan(text: code[i]));
      i++;
    }

    return spans;
  }

  static bool _isWordChar(String ch) {
    final c = ch.codeUnitAt(0);
    return (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) || c == 95;
  }

  static bool _isWordCharOrDot(String ch) {
    return _isWordChar(ch) || ch == '.';
  }
}

/// Input formatter that converts Tab key to spaces.
class _TabInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.contains('\t')) {
      final text = newValue.text.replaceAll('\t', '    ');
      final offset = newValue.selection.baseOffset +
          (text.length - newValue.text.length);
      return TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: offset),
      );
    }
    return newValue;
  }
}
