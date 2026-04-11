import 'package:flutter/widgets.dart';
import '../../models/advanced_config.dart';

/// 将滤镜图层裁剪到用户定义的多边形遮罩区域内（或外）。
class RegionMaskClipper extends StatelessWidget {
  final bool enabled;
  final List<MaskRegion> regions;
  final bool inverted;
  final Widget child;

  const RegionMaskClipper({
    super.key,
    required this.enabled,
    required this.regions,
    required this.inverted,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final activeRegions = regions.where((r) => r.enabled && r.points.length >= 3).toList();
    if (activeRegions.isEmpty) return inverted ? child : const SizedBox.shrink();
    return ClipPath(
      clipper: _RegionMaskCustomClipper(regions: activeRegions, inverted: inverted),
      child: child,
    );
  }
}

class _RegionMaskCustomClipper extends CustomClipper<Path> {
  final List<MaskRegion> regions;
  final bool inverted;

  _RegionMaskCustomClipper({required this.regions, required this.inverted});

  @override
  Path getClip(Size size) {
    Path unionPath = Path();
    for (final region in regions) {
      if (region.points.length < 3) continue;
      final regionPath = Path()..addPolygon(region.points, true);
      unionPath = Path.combine(PathOperation.union, unionPath, regionPath);
    }

    if (inverted) {
      final fullPath = Path()..addRect(Offset.zero & size);
      return Path.combine(PathOperation.difference, fullPath, unionPath);
    }
    return unionPath;
  }

  @override
  bool shouldReclip(covariant _RegionMaskCustomClipper oldClipper) {
    if (oldClipper.inverted != inverted) return true;
    if (oldClipper.regions.length != regions.length) return true;
    for (int i = 0; i < regions.length; i++) {
      final a = oldClipper.regions[i];
      final b = regions[i];
      if (a.id != b.id || a.enabled != b.enabled || a.points.length != b.points.length) return true;
      for (int j = 0; j < b.points.length; j++) {
        if (a.points[j] != b.points[j]) return true;
      }
    }
    return false;
  }
}
