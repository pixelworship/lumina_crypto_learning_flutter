import 'dart:math' as math;

import 'package:flutter/rendering.dart';

import '../../../../data/models/candle.dart';
import 'gap_icon.dart';

/// Reusable painter that draws OHLC candles into [Rect] [plotArea].
///
/// All scaling math lives here, not in the widget. Theme-derived colors
/// (bullish, bearish, gap warning) are passed in via constructor since
/// `paint()` has no access to a `BuildContext`.
class CandlePainter extends CustomPainter {
  CandlePainter({
    required this.candles,
    required this.firstVisibleIndex,
    required this.candleWidth,
    required this.bullishColor,
    required this.bearishColor,
    required this.plotArea,
    required this.gapFillColor,
    required this.gapIconColor,
    this.glowSigma = 4.0,
    this.glowOpacity = 0.55,
    this.priceRangeOverride,
    this.highlightedIndex,
    this.dimAlpha = 0.25,
  });

  final List<Candle> candles;

  /// First (possibly fractional) index visible on the left edge of
  /// [plotArea].
  final double firstVisibleIndex;

  /// Width in pixels per candle slot (body + gap).
  final double candleWidth;

  final Color bullishColor;
  final Color bearishColor;

  /// The drawable region. Y maps min/max prices of currently visible
  /// candles to the bottom/top of this rect.
  final Rect plotArea;

  /// Translucent fill behind each "data unavailable" run.
  final Color gapFillColor;

  /// Tint applied to the centered warning glyph inside gaps.
  final Color gapIconColor;

  /// Standard deviation of the gaussian blur used to draw the glow halo
  /// around each candle.
  final double glowSigma;

  /// Alpha applied to the glow halo (0–1).
  final double glowOpacity;

  /// When non-null, the painter uses this `(min, max)` band for vertical
  /// price-to-y mapping instead of recomputing one from the visible
  /// candles. Lets the chart freeze its vertical axis when auto-scale is
  /// disabled, so out-of-range ticks render outside the plot area.
  final (double, double)? priceRangeOverride;

  /// Index of the candle the user is currently inspecting (long-press
  /// crosshair). When non-null, every other candle is drawn at
  /// [dimAlpha] so the focused one visually pops.
  final int? highlightedIndex;

  /// Alpha multiplier applied to candles that aren't [highlightedIndex]
  /// while a highlight is active. 0 hides them entirely; 1 disables the
  /// dim effect.
  final double dimAlpha;

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty || candleWidth <= 0) return;

    final int visibleCount = (plotArea.width / candleWidth).ceil() + 1;
    final int startIdx =
        firstVisibleIndex.floor().clamp(0, candles.length - 1);
    final int endIdx = (startIdx + visibleCount).clamp(0, candles.length);

    if (startIdx >= endIdx) return;

    // ---- Gap rendering ------------------------------------------------
    // Always draw gap runs first, regardless of whether any real candles
    // are visible. Otherwise a fully-gap window would render as an empty
    // chart. A single warning glyph is centered per contiguous run.
    final Paint gapFillPaint = Paint()..color = gapFillColor;

    int? runStart;
    void flushRun(int runEnd) {
      if (runStart == null) return;
      final int start = runStart!;
      final double leftX =
          plotArea.left + (start - firstVisibleIndex) * candleWidth;
      final double rightX =
          plotArea.left + (runEnd - firstVisibleIndex) * candleWidth;
      final double clippedLeft = leftX.clamp(plotArea.left, plotArea.right);
      final double clippedRight = rightX.clamp(plotArea.left, plotArea.right);
      if (clippedRight > clippedLeft) {
        final Rect rect = Rect.fromLTRB(
          clippedLeft,
          plotArea.top,
          clippedRight,
          plotArea.bottom,
        );
        canvas.drawRect(rect, gapFillPaint);
        canvas.save();
        canvas.clipRect(rect);
        paintGapWarningIcon(canvas, rect, gapIconColor);
        canvas.restore();
      }
      runStart = null;
    }

    for (int i = startIdx; i < endIdx; i++) {
      if (candles[i].isGap) {
        runStart ??= i;
      } else if (runStart != null) {
        flushRun(i);
      }
    }
    flushRun(endIdx);

    // ---- Real-candle rendering ---------------------------------------
    // Prefer an externally-supplied band so the candle layer agrees with
    // the axes painter (and respects the chart's auto-scale toggle).
    // Otherwise auto-fit to the currently visible real candles.
    final double minPrice;
    final double maxPrice;
    if (priceRangeOverride != null) {
      minPrice = priceRangeOverride!.$1;
      maxPrice = priceRangeOverride!.$2;
    } else {
      double computedMin = double.infinity;
      double computedMax = -double.infinity;
      for (int i = startIdx; i < endIdx; i++) {
        final Candle c = candles[i];
        if (c.isGap) continue;
        if (c.low < computedMin) computedMin = c.low;
        if (c.high > computedMax) computedMax = c.high;
      }
      if (computedMin == double.infinity ||
          computedMax == -double.infinity) {
        return;
      }
      final double pad = (computedMax - computedMin) * 0.05;
      final double padding =
          pad == 0 ? math.max(computedMax * 0.005, 0.5) : pad;
      minPrice = computedMin - padding;
      maxPrice = computedMax + padding;
    }
    final double priceRange = maxPrice - minPrice;
    if (priceRange <= 0) return;

    double priceToY(double price) {
      final double ratio = (price - minPrice) / priceRange;
      return plotArea.bottom - ratio * plotArea.height;
    }

    final bool drawGlow = glowSigma > 0 && glowOpacity > 0;
    int latestIdx = candles.length - 1;
    while (latestIdx >= 0 && candles[latestIdx].isGap) {
      latestIdx--;
    }
    final Paint wickPaint = Paint()..strokeWidth = 1.0;
    final Paint bodyPaint = Paint()..style = PaintingStyle.fill;
    final Paint? glowBodyPaint = drawGlow
        ? (Paint()
          ..style = PaintingStyle.fill
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowSigma))
        : null;
    final Paint? glowWickPaint = drawGlow
        ? (Paint()
          ..strokeWidth = 2.0
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowSigma))
        : null;

    canvas.save();
    canvas.clipRect(plotArea.inflate(drawGlow ? glowSigma * 2 : 0));

    for (int i = startIdx; i < endIdx; i++) {
      final Candle c = candles[i];
      if (c.isGap) continue;
      final double centerX = plotArea.left +
          (i - firstVisibleIndex) * candleWidth +
          candleWidth / 2;

      // When a highlight is active, every other candle draws at
      // dimAlpha so the focused one pops. The highlighted candle (and
      // every candle when no highlight is active) draws at full
      // opacity.
      final bool isFocused =
          highlightedIndex == null || highlightedIndex == i;
      final double effectiveAlpha = isFocused ? 1.0 : dimAlpha;

      final Color baseColor = c.isBullish ? bullishColor : bearishColor;
      final Color color = effectiveAlpha >= 1.0
          ? baseColor
          : baseColor.withValues(alpha: effectiveAlpha);
      final double bodyTop = priceToY(math.max(c.open, c.close));
      final double bodyBottom = priceToY(math.min(c.open, c.close));
      final double bodyWidth = math.max(candleWidth * 0.7, 1.0);
      final Rect bodyRect = Rect.fromLTRB(
        centerX - bodyWidth / 2,
        bodyTop,
        centerX + bodyWidth / 2,
        math.max(bodyBottom, bodyTop + 1),
      );

      // Glow only on the most recent (live) candle so it stands out.
      // Skip it while that candle is dimmed — otherwise the halo
      // becomes more visually prominent than the candle body and
      // defeats the highlight effect.
      if (drawGlow && i == latestIdx && isFocused) {
        glowWickPaint!.color = baseColor.withValues(alpha: glowOpacity);
        canvas.drawLine(
          Offset(centerX, priceToY(c.high)),
          Offset(centerX, priceToY(c.low)),
          glowWickPaint,
        );
        glowBodyPaint!.color = baseColor.withValues(alpha: glowOpacity);
        canvas.drawRect(bodyRect, glowBodyPaint);
      }

      wickPaint.color = color;
      canvas.drawLine(
        Offset(centerX, priceToY(c.high)),
        Offset(centerX, priceToY(c.low)),
        wickPaint,
      );
      bodyPaint.color = color;
      canvas.drawRect(bodyRect, bodyPaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CandlePainter oldDelegate) {
    return oldDelegate.candles != candles ||
        oldDelegate.firstVisibleIndex != firstVisibleIndex ||
        oldDelegate.candleWidth != candleWidth ||
        oldDelegate.plotArea != plotArea ||
        oldDelegate.bullishColor != bullishColor ||
        oldDelegate.bearishColor != bearishColor ||
        oldDelegate.gapFillColor != gapFillColor ||
        oldDelegate.gapIconColor != gapIconColor ||
        oldDelegate.glowSigma != glowSigma ||
        oldDelegate.glowOpacity != glowOpacity ||
        oldDelegate.priceRangeOverride != priceRangeOverride ||
        oldDelegate.highlightedIndex != highlightedIndex ||
        oldDelegate.dimAlpha != dimAlpha;
  }

  /// Returns the [minPrice, maxPrice] of currently visible candles (with
  /// padding) so other painters can align their axes.
  static (double, double)? visiblePriceRange({
    required List<Candle> candles,
    required double firstVisibleIndex,
    required double candleWidth,
    required double plotWidth,
  }) {
    if (candles.isEmpty || candleWidth <= 0) return null;
    final int visibleCount = (plotWidth / candleWidth).ceil() + 1;
    final int startIdx =
        firstVisibleIndex.floor().clamp(0, candles.length - 1);
    final int endIdx = (startIdx + visibleCount).clamp(0, candles.length);
    if (startIdx >= endIdx) return null;

    double minPrice = double.infinity;
    double maxPrice = -double.infinity;
    for (int i = startIdx; i < endIdx; i++) {
      final Candle c = candles[i];
      if (c.isGap) continue;
      if (c.low < minPrice) minPrice = c.low;
      if (c.high > maxPrice) maxPrice = c.high;
    }
    if (minPrice == double.infinity || maxPrice == -double.infinity) {
      return null;
    }
    final double pad = (maxPrice - minPrice) * 0.05;
    final double padding = pad == 0 ? math.max(maxPrice * 0.005, 0.5) : pad;
    return (minPrice - padding, maxPrice + padding);
  }
}
