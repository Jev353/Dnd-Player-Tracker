import 'package:flutter/material.dart';

/// Draws a square grid over the whole canvas. Only mount it when the scene's
/// grid is enabled.
///
/// Pass the viewer's [TransformationController] as [transform] so lines keep
/// a constant ~1 screen pixel width at any zoom (a fixed 1px map-space line
/// aliases into moire patterns when the map is zoomed out).
class GridPainter extends CustomPainter {
  GridPainter({
    required this.gridSize,
    this.transform,
    this.color = const Color(0x66D4A64A),
  }) : super(repaint: transform);

  final double gridSize;
  final TransformationController? transform;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (gridSize <= 0) return;
    final scale = transform?.value.getMaxScaleOnAxis() ?? 1.0;
    // Too dense to read on screen: skip rather than render noise.
    if (gridSize * scale < 4) return;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1 / scale
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    for (double x = 0; x <= size.width; x += gridSize) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += gridSize) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(GridPainter old) =>
      old.gridSize != gridSize ||
      old.color != color ||
      old.transform != transform;
}

