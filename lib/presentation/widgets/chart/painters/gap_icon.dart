import 'package:flutter/material.dart';

/// Centers a Material `error_outline` glyph inside [rect], sized to the
/// rect's shorter side and clipped (well, scaled) so it never bleeds out.
/// Skips drawing entirely once the rect gets too small for an icon to be
/// readable — better than rendering a 2-pixel speck.
///
/// Shared between the historical-gap painter (`CandlePainter`) and the
/// live growing-gap painter (`MissingDataPainter`) so the visual treatment
/// stays in lockstep.
void paintGapWarningIcon(Canvas canvas, Rect rect, Color color) {
  const double minRenderableSize = 12.0;
  // Cap the icon so a tall narrow rect doesn't get a comically large
  // glyph and a short wide rect doesn't blow past the rect height.
  final double size = (rect.shortestSide * 0.6).clamp(0.0, 48.0);
  if (size < minRenderableSize) return;

  const IconData iconData = Icons.error_outline;
  final TextPainter tp = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(iconData.codePoint),
      style: TextStyle(
        fontFamily: iconData.fontFamily,
        package: iconData.fontPackage,
        fontSize: size,
        color: color,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(
    canvas,
    Offset(
      rect.center.dx - tp.width / 2,
      rect.center.dy - tp.height / 2,
    ),
  );
}
