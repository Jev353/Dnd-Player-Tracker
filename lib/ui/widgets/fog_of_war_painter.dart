import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Covers the map in fog and punches holes for [revealedRects].
///
/// Players get fully opaque black fog; the GM gets translucent fog so hidden areas
/// and monsters remain visible to them.
class FogOfWarPainter extends CustomPainter {
  const FogOfWarPainter({required this.revealedRects, required this.isGM});

  final List<Rect> revealedRects;
  final bool isGM;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    // The clear blend mode only cuts through the fog if both are drawn in
    // their own layer; otherwise it would erase the map underneath.
    canvas.saveLayer(bounds, Paint());
    canvas.drawRect(
      bounds,
      // Players get solid black: nothing underneath may show through.
      Paint()
        ..color = isGM ? Colors.black.withValues(alpha: 0.55) : Colors.black,
    );
    final clear = Paint()
      ..blendMode = BlendMode.clear
      ..isAntiAlias = true;
    for (final r in revealedRects) {
      canvas.drawOval(r, clear);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(FogOfWarPainter old) =>
      old.isGM != isGM || !listEquals(old.revealedRects, revealedRects);
}
