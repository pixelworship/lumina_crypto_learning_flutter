import 'package:flutter/material.dart';

import 'gap_icon.dart';

/// Renders a red "data unavailable" rectangle starting at
/// [startCandleIndex] (i.e. immediately after the last real candle) and
/// spanning [gapInCandles] candle widths.
///
/// Stays clipped to [plotArea] so it never paints over axis labels.
class MissingDataPainter extends CustomPainter {
  MissingDataPainter({
    required this.startCandleIndex,
    required this.firstVisibleIndex,
    required this.candleWidth,
    required this.gapInCandles,
    required this.plotArea,
    required this.fillColor,
    required this.iconColor,
  });

  final double startCandleIndex;
  final double firstVisibleIndex;
  final double candleWidth;
  final double gapInCandles;
  final Rect plotArea;
  final Color fillColor;

  /// Tint applied to the centered warning glyph.
  final Color iconColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (gapInCandles <= 0 || candleWidth <= 0) return;

    final double leftX = plotArea.left +
        (startCandleIndex - firstVisibleIndex) * candleWidth;
    final double rightX = leftX + gapInCandles * candleWidth;

    final double clippedLeft = leftX.clamp(plotArea.left, plotArea.right);
    final double clippedRight = rightX.clamp(plotArea.left, plotArea.right);
    if (clippedRight - clippedLeft <= 0) return;

    final Rect rect = Rect.fromLTRB(
      clippedLeft,
      plotArea.top,
      clippedRight,
      plotArea.bottom,
    );

    canvas.save();
    canvas.clipRect(rect);

    canvas.drawRect(rect, Paint()..color = fillColor);
    paintGapWarningIcon(canvas, rect, iconColor);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant MissingDataPainter old) =>
      old.startCandleIndex != startCandleIndex ||
      old.firstVisibleIndex != firstVisibleIndex ||
      old.candleWidth != candleWidth ||
      old.gapInCandles != gapInCandles ||
      old.plotArea != plotArea ||
      old.fillColor != fillColor ||
      old.iconColor != iconColor;
}
