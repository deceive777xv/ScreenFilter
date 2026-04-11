import 'package:flutter/material.dart';
import '../color_picker/color_picker_panel.dart';

/// Panel showing injected uniform variables with real-time values.
class UniformControlsPanel extends StatelessWidget {
  final double elapsedTime;
  final Size resolution;
  final Offset mousePosition;
  final Color accentColor;
  final bool isRunning;
  final VoidCallback onToggleRunning;
  final VoidCallback onResetTime;
  final ValueChanged<Color> onAccentColorChanged;

  const UniformControlsPanel({
    super.key,
    required this.elapsedTime,
    required this.resolution,
    required this.mousePosition,
    required this.accentColor,
    required this.isRunning,
    required this.onToggleRunning,
    required this.onResetTime,
    required this.onAccentColorChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF313244)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title bar
          Row(
            children: [
              const Icon(Icons.input, size: 14, color: Color(0xFF89B4FA)),
              const SizedBox(width: 6),
              const Text(
                'Uniforms',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFCDD6F4),
                ),
              ),
              const Spacer(),
              _iconButton(
                icon: isRunning ? Icons.pause : Icons.play_arrow,
                tooltip: isRunning ? '暂停' : '播放',
                onTap: onToggleRunning,
              ),
              const SizedBox(width: 4),
              _iconButton(
                icon: Icons.replay,
                tooltip: '重置时间',
                onTap: onResetTime,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _UniformRow(
            name: 'u_Time',
            type: 'float',
            value: elapsedTime.toStringAsFixed(2),
            color: const Color(0xFFFAB387),
          ),
          const SizedBox(height: 6),
          _UniformRow(
            name: 'u_Resolution',
            type: 'float2',
            value:
                '${resolution.width.toInt()} × ${resolution.height.toInt()}',
            color: const Color(0xFF89B4FA),
          ),
          const SizedBox(height: 6),
          _UniformRow(
            name: 'u_Mouse',
            type: 'float2',
            value:
                '${mousePosition.dx.toStringAsFixed(3)}, ${mousePosition.dy.toStringAsFixed(3)}',
            color: const Color(0xFFA6E3A1),
          ),
          const SizedBox(height: 6),
          _buildAccentColorRow(context),
        ],
      ),
    );
  }

  Widget _buildAccentColorRow(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: const Color(0xFFF38BA8),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'u_AccentColor',
              style: TextStyle(
                fontFamily: 'Consolas',
                fontSize: 12,
                color: Color(0xFFF38BA8),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'float4',
              style: TextStyle(
                fontFamily: 'Consolas',
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.3),
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => _showColorPickerDialog(context),
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF45475A)),
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 24, top: 3),
          child: Text(
            '(${accentColor.r.toStringAsFixed(2)}, '
            '${accentColor.g.toStringAsFixed(2)}, '
            '${accentColor.b.toStringAsFixed(2)}, '
            '${accentColor.a.toStringAsFixed(2)})',
            style: const TextStyle(
              fontFamily: 'Consolas',
              fontSize: 11,
              color: Color(0xFF9399B2),
            ),
          ),
        ),
      ],
    );
  }

  void _showColorPickerDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: const Color(0xFF1E1E2E),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: 340,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Row(
                  children: [
                    const Icon(Icons.palette,
                        size: 18, color: Color(0xFFF38BA8)),
                    const SizedBox(width: 8),
                    const Text(
                      'u_AccentColor',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFCDD6F4),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close,
                          size: 18, color: Color(0xFF6C7086)),
                      onPressed: () => Navigator.of(ctx).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ColorPickerPanel(
                  color: accentColor,
                  paletteHeight: 180,
                  onChanged: onAccentColorChanged,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _iconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16, color: const Color(0xFF9399B2)),
        ),
      ),
    );
  }
}

class _UniformRow extends StatelessWidget {
  final String name;
  final String type;
  final String value;
  final Color color;

  const _UniformRow({
    required this.name,
    required this.type,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          name,
          style: TextStyle(
            fontFamily: 'Consolas',
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          type,
          style: TextStyle(
            fontFamily: 'Consolas',
            fontSize: 11,
            color: Colors.white.withValues(alpha: 0.3),
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'Consolas',
            fontSize: 12,
            color: Color(0xFF9399B2),
          ),
        ),
      ],
    );
  }
}
