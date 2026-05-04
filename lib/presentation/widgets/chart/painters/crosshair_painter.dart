import 'dart:math' as math;

import 'package:flutter/rendering.dart';

/// Draws a full-canvas crosshair (dashed horizontal + vertical lines) at
/// [position]. No-op when [position] is null.
class CrosshairPainter extends CustomPainter {
  CrosshairPainter({
    required this.position,
    required this.color,
    this.dashLength = 5.0,
    this.gapLength = 4.0,
    this.strokeWidth = 1.0,
  });

  final Offset? position;
  final Color color;
  final double dashLength;
  final double gapLength;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset? p = position;
    if (p == null) return;

    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..isAntiAlias = false;

    _drawDashed(canvas, Offset(p.dx, 0), Offset(p.dx, size.height), paint);
    _drawDashed(canvas, Offset(0, p.dy), Offset(size.width, p.dy), paint);
  }

  void _drawDashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    final Offset delta = b - a;
    final double distance = delta.distance;
    if (distance <= 0) return;
    final Offset dir = delta / distance;
    double d = 0.0;
    while (d < distance) {
      final double endD = math.min(d + dashLength, distance);
      canvas.drawLine(a + dir * d, a + dir * endD, paint);
      d += dashLength + gapLength;
    }
  }

  @override
  bool shouldRepaint(covariant CrosshairPainter old) =>
      old.position != position ||
      old.color != color ||
      old.dashLength != dashLength ||
      old.gapLength != gapLength ||
      old.strokeWidth != strokeWidth;
}
