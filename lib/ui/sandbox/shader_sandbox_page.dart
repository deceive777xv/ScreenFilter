import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import '../../models/shader_preset.dart';
import '../../services/shader_filter_service.dart';
import 'shader_code_editor.dart';
import 'uniform_controls_panel.dart';

/// Shader Sandbox — a Shadertoy-like environment for editing,
/// compiling, and previewing HLSL shaders in real time.
class ShaderSandboxPage extends StatefulWidget {
  final ShaderFilterService service;

  const ShaderSandboxPage({super.key, required this.service});

  @override
  State<ShaderSandboxPage> createState() => _ShaderSandboxPageState();
}

class _ShaderSandboxPageState extends State<ShaderSandboxPage> {
  ShaderFilterService get _service => widget.service;

  // ── Code state ─────────────────────────────────────────────────
  late String _currentCode;
  String? _compileError;
  bool _compileSuccess = false;

  // ── Uniform state ──────────────────────────────────────────────
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _timer;
  bool _isRunning = true;
  double _elapsedTime = 0;
  Offset _mousePosition = Offset.zero;
  Color _accentColor = const Color(0xFFFF8040);

  // ── Preview state ──────────────────────────────────────────────
  ui.Image? _previewImage;
  static const int _previewWidth = 320;
  static const int _previewHeight = 180;

  // ── Filter mode ────────────────────────────────────────────────
  FilterApplyMode _filterMode = FilterApplyMode.none;

  // ── Editor ref ─────────────────────────────────────────────────
  final GlobalKey<_ShaderCodeEditorAccessState> _editorKey = GlobalKey();

  // ── Compile debounce ───────────────────────────────────────────
  Timer? _compileDebounce;

  @override
  void initState() {
    super.initState();
    _currentCode = ShaderPreset.defaultShaderCode;
    _filterMode = _service.mode;
    _accentColor = _service.accentColor;

    // We take over rendering while the page is alive.
    _service.pauseOwnTimer();

    _compileCurrentShader();
    _startAnimation();
  }

  void _startAnimation() {
    _stopwatch.start();
    _timer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      if (!_isRunning) return;
      setState(() {
        _elapsedTime = _stopwatch.elapsedMilliseconds / 1000.0;
      });
      _renderPreview();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _compileDebounce?.cancel();
    _stopwatch.stop();
    // Don't dispose the engine — service owns it.
    // Let the service resume its own timer if needed.
    _service.resumeOwnTimerIfNeeded();
    super.dispose();
  }

  // ── Compilation ────────────────────────────────────────────────

  void _compileCurrentShader() {
    final result = _service.compileShader(_currentCode);
    setState(() {
      _compileSuccess = result.success;
      _compileError = result.success ? null : result.errorMessage;
    });
  }

  // ── Rendering ──────────────────────────────────────────────────

  void _renderPreview() {
    if (!_compileSuccess) return;

    // 1) Render preview at small resolution.
    final pixels = _service.renderFrame(
      width: _previewWidth,
      height: _previewHeight,
      time: _elapsedTime,
      mouseX: _mousePosition.dx,
      mouseY: _mousePosition.dy,
      accentColor: _accentColor,
    );

    if (pixels != null) {
      _createPreviewImage(pixels, _previewWidth, _previewHeight);
    }

    // 2) If filter is active (dynamic), also render at screen res.
    if (_filterMode == FilterApplyMode.dynamic) {
      _renderFilterFrame();
    }
  }

  void _renderFilterFrame() {
    final screenSize = _service.screenSize;
    if (screenSize == Size.zero) return;

    final w = screenSize.width.toInt();
    final h = screenSize.height.toInt();
    final mouse = _service.getGlobalMouseNormalized();
    final pixels = _service.renderFrame(
      width: w,
      height: h,
      time: _elapsedTime,
      mouseX: mouse.dx,
      mouseY: mouse.dy,
      accentColor: _accentColor,
    );

    if (pixels != null) {
      _createFilterImage(pixels, w, h);
    }
  }

  Future<void> _createPreviewImage(Uint8List pixels, int w, int h) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels, w, h, ui.PixelFormat.rgba8888,
      (image) => completer.complete(image),
    );
    final image = await completer.future;
    if (mounted) {
      setState(() => _previewImage = image);
    }
  }

  Future<void> _createFilterImage(Uint8List pixels, int w, int h) async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels, w, h, ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final image = await completer.future;
    // Guard against stale async decode completing after filter was stopped.
    if (_service.mode != FilterApplyMode.none) {
      _service.filterImageNotifier.value = image;
    }
  }

  // ── Code change ────────────────────────────────────────────────

  void _onCodeChanged(String code) {
    _currentCode = code;
    _compileDebounce?.cancel();
    _compileDebounce = Timer(const Duration(milliseconds: 500), () {
      _compileCurrentShader();
    });
  }

  // ── Playback ───────────────────────────────────────────────────

  void _toggleRunning() {
    setState(() {
      _isRunning = !_isRunning;
      if (_isRunning) {
        _stopwatch.start();
      } else {
        _stopwatch.stop();
      }
    });
  }

  void _resetTime() {
    _stopwatch.reset();
    if (_isRunning) _stopwatch.start();
    setState(() => _elapsedTime = 0);
  }

  // ── Filter apply ──────────────────────────────────────────────

  void _applyFilter(FilterApplyMode mode) {
    final screenSize = MediaQuery.of(context).size;
    _service.updateScreenSize(screenSize);
    _service.updateAccentColor(_accentColor);

    setState(() => _filterMode = mode);

    if (mode == FilterApplyMode.none) {
      _service.stopFilter();
      return;
    }

    if (mode == FilterApplyMode.static) {
      // Render one frame at screen res and freeze.
      _service.applyFilter(FilterApplyMode.static, screenSize, _accentColor);
      // Also do a local render so the notifier gets a screen-res image.
      if (_compileSuccess) {
        final w = screenSize.width.toInt();
        final h = screenSize.height.toInt();
        final pixels = _service.renderFrame(
          width: w,
          height: h,
          time: _elapsedTime,
          mouseX: 0.5,
          mouseY: 0.5,
          accentColor: _accentColor,
        );
        if (pixels != null) {
          _createFilterImage(pixels, w, h);
        }
      }
      return;
    }

    // Dynamic — service knows, but while we're alive we render.
    _service.applyFilter(FilterApplyMode.dynamic, screenSize, _accentColor);
    _service.pauseOwnTimer(); // we handle it
  }

  // ── Export / Import ────────────────────────────────────────────

  Future<void> _exportShader() async {
    final preset = ShaderPreset(
      name: 'My Shader',
      author: '',
      description: '',
      code: _currentCode,
      accentColor: _accentColor,
    );

    const typeGroup = XTypeGroup(
      label: 'Shader Preset',
      extensions: ['shader'],
    );
    final location = await getSaveLocation(
      suggestedName: 'my_shader.shader',
      acceptedTypeGroups: [typeGroup],
    );
    if (location == null) return;

    await preset.exportToFile(location.path);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已导出: ${location.path}'),
          backgroundColor: const Color(0xFF1E1E2E),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _importShader() async {
    const typeGroup = XTypeGroup(
      label: 'Shader Preset',
      extensions: ['shader'],
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null) return;

    try {
      final preset = await ShaderPreset.importFromFile(file.path);
      setState(() {
        _currentCode = preset.code;
        _accentColor = preset.accentColor;
        _compileError = null;
      });
      _editorKey.currentState?.setCode(preset.code);
      _compileCurrentShader();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已导入: ${preset.name}'),
            backgroundColor: const Color(0xFF1E1E2E),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导入失败: $e'),
            backgroundColor: const Color(0xFF7F1D1D),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _resetToDefault() {
    setState(() {
      _currentCode = ShaderPreset.defaultShaderCode;
      _compileError = null;
    });
    _editorKey.currentState?.setCode(ShaderPreset.defaultShaderCode);
    _compileCurrentShader();
  }

  // ── Build ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Top toolbar: compile + status + filter mode
          _buildTopToolbar(),
          const SizedBox(height: 8),
          // Bottom toolbar: import / export / reset
          _buildBottomToolbar(),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Code editor (left)
                Expanded(
                  flex: 3,
                  child: _ShaderCodeEditorAccess(
                    key: _editorKey,
                    initialCode: _currentCode,
                    onCodeChanged: _onCodeChanged,
                    errorMessage: _compileError,
                  ),
                ),
                const SizedBox(width: 12),
                // Right panel: preview + uniforms
                SizedBox(
                  width: 260,
                  child: Column(
                    children: [
                      _buildPreviewPanel(),
                      const SizedBox(height: 10),
                      Expanded(
                        child: UniformControlsPanel(
                          elapsedTime: _elapsedTime,
                          resolution: Size(
                              _previewWidth.toDouble(),
                              _previewHeight.toDouble()),
                          mousePosition: _mousePosition,
                          accentColor: _accentColor,
                          isRunning: _isRunning,
                          onToggleRunning: _toggleRunning,
                          onResetTime: _resetTime,
                          onAccentColorChanged: (c) {
                            setState(() => _accentColor = c);
                            _service.updateAccentColor(c);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Top toolbar ────────────────────────────────────────────────

  Widget _buildTopToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF181825),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF313244)),
      ),
      child: Row(
        children: [
          // Compile
          _toolbarButton(
            icon: Icons.play_circle_outline,
            label: '编译',
            color: _compileSuccess
                ? const Color(0xFFA6E3A1)
                : const Color(0xFF89B4FA),
            onTap: _compileCurrentShader,
          ),
          const SizedBox(width: 8),
          // Status pill
          _buildStatusPill(),
          if (!_service.isEngineReady) ...[
            const SizedBox(width: 8),
            _buildWarningPill(),
          ],
          const SizedBox(width: 12),
          // Separator
          Container(width: 1, height: 20, color: const Color(0xFF313244)),
          const SizedBox(width: 12),
          // Filter mode buttons
          _buildFilterButtons(),
        ],
      ),
    );
  }

  // ── Bottom toolbar ─────────────────────────────────────────────

  Widget _buildBottomToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF181825),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF313244)),
      ),
      child: Row(
        children: [
          const Icon(Icons.folder_outlined,
              size: 14, color: Color(0xFF6C7086)),
          const SizedBox(width: 6),
          const Text('文件',
              style: TextStyle(fontSize: 11, color: Color(0xFF6C7086))),
          const SizedBox(width: 12),
          _toolbarButton(
              icon: Icons.file_open_outlined,
              label: '导入',
              onTap: _importShader),
          const SizedBox(width: 6),
          _toolbarButton(
              icon: Icons.save_outlined,
              label: '导出 .shader',
              onTap: _exportShader),
          const Spacer(),
          _toolbarButton(
              icon: Icons.restart_alt,
              label: '重置代码',
              color: const Color(0xFFEF4444).withValues(alpha: 0.7),
              onTap: _resetToDefault),
        ],
      ),
    );
  }

  Widget _buildFilterButtons() {
    if (_filterMode != FilterApplyMode.none) {
      final label = _filterMode == FilterApplyMode.static
          ? '取消滤镜 (静态)'
          : '取消滤镜 (动态)';
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.filter_alt,
              size: 14, color: Color(0xFFF9E2AF)),
          const SizedBox(width: 6),
          Text(
            _filterMode == FilterApplyMode.static ? '静态模式' : '动态模式',
            style: const TextStyle(
                fontSize: 11,
                color: Color(0xFFF9E2AF),
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          _toolbarButton(
            icon: Icons.filter_alt_off,
            label: label,
            color: const Color(0xFFF9E2AF),
            onTap: () => _applyFilter(FilterApplyMode.none),
          ),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.filter_alt_outlined,
            size: 14, color: Color(0xFF6C7086)),
        const SizedBox(width: 6),
        const Text('应用滤镜',
            style: TextStyle(fontSize: 11, color: Color(0xFF6C7086))),
        const SizedBox(width: 8),
        _toolbarButton(
          icon: Icons.photo_filter_outlined,
          label: '静态',
          onTap: _compileSuccess
              ? () => _applyFilter(FilterApplyMode.static)
              : null,
        ),
        const SizedBox(width: 6),
        _toolbarButton(
          icon: Icons.movie_filter_outlined,
          label: '动态',
          onTap: _compileSuccess
              ? () => _applyFilter(FilterApplyMode.dynamic)
              : null,
        ),
      ],
    );
  }

  Widget _buildStatusPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _compileSuccess
            ? const Color(0xFF166534).withValues(alpha: 0.3)
            : (_compileError != null
                ? const Color(0xFF7F1D1D).withValues(alpha: 0.3)
                : const Color(0xFF313244)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _compileSuccess
                ? Icons.check_circle
                : (_compileError != null
                    ? Icons.error
                    : Icons.circle_outlined),
            size: 12,
            color: _compileSuccess
                ? const Color(0xFFA6E3A1)
                : (_compileError != null
                    ? const Color(0xFFEF4444)
                    : const Color(0xFF9399B2)),
          ),
          const SizedBox(width: 4),
          Text(
            _compileSuccess
                ? '编译成功'
                : (_compileError != null ? '编译错误' : '等待编译'),
            style: TextStyle(
              fontSize: 11,
              color: _compileSuccess
                  ? const Color(0xFFA6E3A1)
                  : (_compileError != null
                      ? const Color(0xFFEF4444)
                      : const Color(0xFF9399B2)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF92400E).withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber, size: 12, color: Color(0xFFFBBF24)),
          SizedBox(width: 4),
          Text('DX11引擎未加载',
              style: TextStyle(fontSize: 11, color: Color(0xFFFBBF24))),
        ],
      ),
    );
  }

  Widget _toolbarButton({
    required IconData icon,
    required String label,
    Color? color,
    required VoidCallback? onTap,
  }) {
    final c = color ?? const Color(0xFF9399B2);
    final disabled = onTap == null;
    final displayColor = disabled ? c.withValues(alpha: 0.3) : c;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF313244)),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: displayColor),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 12, color: displayColor)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Preview panel ──────────────────────────────────────────────

  Widget _buildPreviewPanel() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF11111B),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF313244)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: const BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: Color(0xFF313244))),
              ),
              child: const Row(
                children: [
                  Icon(Icons.tv, size: 13, color: Color(0xFF89B4FA)),
                  SizedBox(width: 6),
                  Text('预览',
                      style: TextStyle(
                          fontSize: 12, color: Color(0xFFCDD6F4))),
                ],
              ),
            ),
            ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(7),
                bottomRight: Radius.circular(7),
              ),
              child: MouseRegion(
                onHover: (event) {
                  setState(() {
                    _mousePosition = Offset(
                      (event.localPosition.dx / 260).clamp(0, 1),
                      (event.localPosition.dy / 146).clamp(0, 1),
                    );
                  });
                },
                child: Container(
                  width: 260,
                  height: 146,
                  color: Colors.black,
                  child: _buildPreviewContent(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewContent() {
    if (!_service.isEngineReady) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videogame_asset_off,
                size: 32, color: Color(0xFF45475A)),
            SizedBox(height: 8),
            Text(
              'DX11 引擎未就绪\n编辑器仍可使用',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 11, color: Color(0xFF6C7086), height: 1.4),
            ),
          ],
        ),
      );
    }

    if (!_compileSuccess) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.code_off, size: 32, color: Color(0xFFEF4444)),
            SizedBox(height: 8),
            Text(
              'Shader 编译失败\n请修复错误',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 11, color: Color(0xFF6C7086), height: 1.4),
            ),
          ],
        ),
      );
    }

    if (_previewImage != null) {
      return RawImage(
        image: _previewImage,
        fit: BoxFit.fill,
        width: 260,
        height: 146,
      );
    }

    return const Center(
      child: CircularProgressIndicator(
          strokeWidth: 2, color: Color(0xFF89B4FA)),
    );
  }
}

/// Wrapper to expose setCode via GlobalKey.
class _ShaderCodeEditorAccess extends StatefulWidget {
  final String initialCode;
  final ValueChanged<String> onCodeChanged;
  final String? errorMessage;

  const _ShaderCodeEditorAccess({
    super.key,
    required this.initialCode,
    required this.onCodeChanged,
    this.errorMessage,
  });

  @override
  State<_ShaderCodeEditorAccess> createState() =>
      _ShaderCodeEditorAccessState();
}

class _ShaderCodeEditorAccessState extends State<_ShaderCodeEditorAccess> {
  final GlobalKey<ShaderCodeEditorState> _innerKey = GlobalKey();

  void setCode(String code) {
    _innerKey.currentState?.setCode(code);
  }

  @override
  Widget build(BuildContext context) {
    return ShaderCodeEditor(
      key: _innerKey,
      initialCode: widget.initialCode,
      onCodeChanged: widget.onCodeChanged,
      errorMessage: widget.errorMessage,
    );
  }
}
