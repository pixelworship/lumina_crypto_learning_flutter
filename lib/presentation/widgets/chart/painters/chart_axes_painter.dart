import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

import '../../../../core/utils/formatters.dart';
import '../../../../data/models/candle.dart';
import '../../../../data/models/timeframe.dart';

/// Draws price grid lines + axis labels behind the candles.
class ChartAxesPainter extends CustomPainter {
  ChartAxesPainter({
    required this.candles,
    required this.firstVisibleIndex,
    required this.candleWidth,
    required this.minPrice,
    required this.maxPrice,
    required this.plotArea,
    required this.gridColor,
    required this.labelStyle,
    required this.timeframe,
    this.priceTickCount = 5,
    this.minLabelSpacingPx = 64,
    this.labelHorizontalPadding = 8,
  });

  final List<Candle> candles;
  final double firstVisibleIndex;
  final double candleWidth;
  final double minPrice;
  final double maxPrice;
  final Rect plotArea;
  final Color gridColor;
  final TextStyle labelStyle;
  final int priceTickCount;

  /// Active timeframe — drives how granular the time-axis labels need to
  /// be. Sub-minute buckets need seconds, multi-day spans need a date,
  /// otherwise `h:mm` is enough.
  final Timeframe timeframe;

  /// Minimum horizontal pixels between adjacent time labels. Drives how
  /// many candles each label step covers.
  final double minLabelSpacingPx;

  /// Extra padding (px) added when computing whether a label fits before
  /// the next label. Prevents tight collisions at zoom boundaries.
  final double labelHorizontalPadding;

  static final intl.DateFormat _secondsFmt = intl.DateFormat('h:mm:ss');
  static final intl.DateFormat _minuteFmt = intl.DateFormat('h:mm');
  static final intl.DateFormat _dateTimeFmt = intl.DateFormat('MMM d, h:mm');
  static final intl.DateFormat _dateFmt = intl.DateFormat('MMM d');

  /// Returns the label for [timestamp], deciding granularity based on the
  /// active [timeframe] and the time span of the visible window. Indexes
  /// [firstIdx]..[lastIdx] in [candles] define what's currently on screen
  /// — when those cross a date boundary we include the date in the label.
  String _formatTimestamp(
    DateTime timestamp, {
    required int firstIdx,
    required int lastIdx,
  }) {
    final bool crossesDate = _visibleCrossesDateBoundary(firstIdx, lastIdx);
    if (timeframe.duration < const Duration(minutes: 1)) {
      // Sub-minute buckets: seconds matter. Date is rarely useful here
      // since a screenful covers minutes, but include it if we somehow
      // span a day boundary.
      return crossesDate
          ? '${_dateFmt.format(timestamp)} ${_secondsFmt.format(timestamp)}'
          : _secondsFmt.format(timestamp);
    }
    return crossesDate
        ? _dateTimeFmt.format(timestamp)
        : _minuteFmt.format(timestamp);
  }

  bool _visibleCrossesDateBoundary(int firstIdx, int lastIdx) {
    if (firstIdx < 0 || lastIdx < firstIdx || lastIdx >= candles.length) {
      return false;
    }
    final DateTime first = candles[firstIdx].timestamp;
    final DateTime last = candles[lastIdx].timestamp;
    return first.year != last.year ||
        first.month != last.month ||
        first.day != last.day;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double priceRange = maxPrice - minPrice;
    if (priceRange <= 0) return;

    final Paint gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.5;

    for (int i = 0; i <= priceTickCount; i++) {
      final double t = i / priceTickCount;
      final double price = maxPrice - t * priceRange;
      final double y = plotArea.top + t * plotArea.height;

      canvas.drawLine(
        Offset(plotArea.left, y),
        Offset(plotArea.right, y),
        gridPaint,
      );

      final TextPainter labelPainter = TextPainter(
        text: TextSpan(
          // Compact form keeps the right-axis labels readable in
          // the 64-px price-gutter even for high-magnitude assets
          // (e.g. `$64.3K` instead of `$64,289.50`).
          text: Formatters.compactCurrency(price),
          style: labelStyle,
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width - plotArea.right);
      labelPainter.paint(
        canvas,
        Offset(plotArea.right + 4, y - labelPainter.height / 2),
      );
    }

    if (candles.isEmpty || candleWidth <= 0) return;

    final int visibleCount = (plotArea.width / candleWidth).ceil() + 1;
    final int startIdx =
        firstVisibleIndex.floor().clamp(0, candles.length - 1);
    final int endIdx = (startIdx + visibleCount).clamp(0, candles.length);

    final int stepInCandles = math.max(
      1,
      (minLabelSpacingPx / candleWidth).ceil(),
    );

    // Anchor to multiples of the step so labels stay pinned to specific
    // candle indices instead of drifting under the user's finger.
    final int firstAlignedIdx =
        ((startIdx + stepInCandles - 1) ~/ stepInCandles) * stepInCandles;

    double? lastLabelRight;
    for (int i = firstAlignedIdx; i < endIdx; i += stepInCandles) {
      if (i < 0 || i >= candles.length) continue;
      if (candles[i].isGap) continue;

      final double centerX = plotArea.left +
          (i - firstVisibleIndex) * candleWidth +
          candleWidth / 2;

      final String timeLabel = _formatTimestamp(
        candles[i].timestamp,
        firstIdx: startIdx,
        lastIdx: endIdx - 1,
      );
      final TextPainter tp = TextPainter(
        text: TextSpan(text: timeLabel, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();

      final double left = centerX - tp.width / 2;
      final double right = centerX + tp.width / 2;

      if (right < plotArea.left || left > plotArea.right) continue;

      // Defensive: if step rounding still produces a collision (e.g.
      // very long labels), drop this one rather than overlap.
      if (lastLabelRight != null &&
          left < lastLabelRight + labelHorizontalPadding) {
        continue;
      }

      tp.paint(canvas, Offset(left, plotArea.bottom + 4));
      lastLabelRight = right;
    }
  }

  @override
  bool shouldRepaint(covariant ChartAxesPainter oldDelegate) {
    return oldDelegate.candles != candles ||
        oldDelegate.firstVisibleIndex != firstVisibleIndex ||
        oldDelegate.candleWidth != candleWidth ||
        oldDelegate.minPrice != minPrice ||
        oldDelegate.maxPrice != maxPrice ||
        oldDelegate.plotArea != plotArea ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.labelStyle != labelStyle ||
        oldDelegate.timeframe != timeframe ||
        oldDelegate.minLabelSpacingPx != minLabelSpacingPx ||
        oldDelegate.labelHorizontalPadding != labelHorizontalPadding;
  }
}
