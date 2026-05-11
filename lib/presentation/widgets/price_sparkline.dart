import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/models/price_point.dart';
import '../../design_system/lumina_ui.dart';
import '../blocs/debug/sparkline_open_line_cubit.dart';

/// Compact area-line chart used inside cards (e.g. "Total Balance").
///
/// When [showGrid] is true the chart layers two extra visual cues on
/// top of the gradient fill:
///   * A fading dot lattice in the region strictly under the line —
///     a 6-pixel square grid of tiny line-colored circles masked so
///     dots above the line never paint, with a global vertical alpha
///     falloff so dots near the chart's bottom edge fade to fully
///     transparent.
///   * A dashed horizontal "open" line anchored at the first
///     sparkline price (i.e. the value the window opened at) so the
///     viewer can read at a glance whether we're currently above or
///     below the period's opening price.
/// Both cues use the resolved line color so they read as part of the
/// same chart, not a separate overlay.
class PriceSparkline extends StatelessWidget {
  const PriceSparkline({
    super.key,
    required this.points,
    this.lineColor,
    this.fillGradient,
    this.height = 90,
    this.showGrid = true,
    this.isPositive,
  });

  final List<PricePoint> points;
  final Color? lineColor;
  final LinearGradient? fillGradient;
  final double height;
  final bool showGrid;

  /// Authoritative "stock is up for the day" signal from the call
  /// site (e.g. `BalanceSummary.isPositive`, which reads
  /// `change24hPercent >= 0`). When null, the widget falls back to
  /// comparing the last visible point against the first — close to
  /// correct but susceptible to drift if the sparkline window doesn't
  /// perfectly span 24h. Callers that already track a 24h change
  /// should always pass this explicitly so the line color stays
  /// consistent with the change pill rendered alongside.
  final bool? isPositive;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    if (points.isEmpty) {
      return SizedBox(height: height);
    }

    final List<FlSpot> spots = <FlSpot>[
      for (int i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].price),
    ];

    final double minY = points
        .map((PricePoint p) => p.price)
        .reduce((double a, double b) => a < b ? a : b);
    final double maxY = points
        .map((PricePoint p) => p.price)
        .reduce((double a, double b) => a > b ? a : b);
    final double padding = (maxY - minY) * 0.15 + 0.001;
    final double effMinY = minY - padding;
    final double effMaxY = maxY + padding;

    // Match the up/down color rule used everywhere else in the app's
    // line charts: green when the asset/balance is up for the period,
    // red otherwise. Prefer the explicit `isPositive` from the call
    // site (authoritative "change for the day" source) and fall back
    // to comparing last vs first point — same reference the dashed
    // open marker sits at — when no signal was provided.
    // Single-point windows fall through as positive so the card
    // never flashes red while the sparkline is hydrating. An explicit
    // `lineColor` override still wins.
    final bool resolvedIsPositive = isPositive ??
        (points.length < 2
            ? true
            : points.last.price >= points.first.price);
    final Color resolvedLineColor = lineColor ??
        (resolvedIsPositive
            ? t.colors.chartCandleBullish
            : t.colors.chartCandleBearish);
    // The dashed open-price reference line is hidden in the shipping
    // UI and only flips on while the user has the debug FAB toggled.
    // Watching the cubit means a tap on the FAB triggers a single
    // repaint frame across every visible sparkline.
    final bool showOpenLine = context.watch<SparklineOpenLineCubit>().state;

    return SizedBox(
      height: height,
      child: Stack(
        children: <Widget>[
          LineChart(
            LineChartData(
              minX: 0,
              maxX: (points.length - 1).toDouble(),
              minY: effMinY,
              maxY: effMaxY,
              gridData: const FlGridData(show: false),
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: <LineChartBarData>[
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  curveSmoothness: 0.32,
                  color: resolvedLineColor,
                  barWidth: 2.4,
                  dotData: const FlDotData(show: false),
                  // Suppress the below-line gradient when the dot
                  // grid is on. Both are tinted with the same line
                  // color, so layering them produces cyan-on-cyan
                  // soup where neither the dots nor the open-price
                  // dashed line read clearly against the gradient.
                  // With the gradient hidden the dots and dashed
                  // line sit on the card's dark surface and read
                  // unambiguously as line-colored markers.
                  belowBarData: BarAreaData(
                    show: !showGrid,
                    gradient: fillGradient ?? t.colors.chartFillGradient,
                  ),
                ),
              ],
            ),
          ),
          if (showGrid)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _SparklineDotGridPainter(
                    points: points,
                    minY: effMinY,
                    maxY: effMaxY,
                    color: resolvedLineColor,
                    openPrice: points.first.price,
                    showOpenLine: showOpenLine,
                    // The dashed open-price line uses the design
                    // system's neutral "axis label" gray rather than
                    // the line color, so it reads as a subdued
                    // reference marker (akin to a y-axis tick) and
                    // never competes hue-for-hue with the live line.
                    dashColor: t.colors.contentTertiary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Paints a fading dot grid in the area strictly below the sparkline.
///
/// The grid lives on a fixed 6-pixel lattice in the chart's local
/// coordinate space — the same lattice regardless of where the line
/// sits — so adjacent sparklines (e.g. several balance cards stacked)
/// read as a single connected dot field rather than disjoint pockets.
///
/// Two visibility filters apply per dot:
///   * **Line mask**: dots whose y is above the linearly-interpolated
///     pixel-space line at the dot's x are skipped entirely. The line
///     itself is the rendered LineChart's smoothed curve, but the
///     mask uses the un-smoothed polyline as a close-enough
///     approximation. Any tiny discrepancy is invisible thanks to the
///     fade and the dots' 1px radius.
///   * **Vertical fade**: a global linear falloff from [peakAlpha] at
///     y=0 to 0 at y=height. We use absolute y (not distance below the
///     line) so the dot field reads as one consistent gradient — a
///     local-distance fade would look uneven because line height
///     varies across columns.
class _SparklineDotGridPainter extends CustomPainter {
  _SparklineDotGridPainter({
    required this.points,
    required this.minY,
    required this.maxY,
    required this.color,
    required this.openPrice,
    required this.dashColor,
    required this.showOpenLine,
  });

  final List<PricePoint> points;
  final double minY;
  final double maxY;
  final Color color;

  /// Color used to stroke the dashed open-price reference line. Kept
  /// independent of [color] so the dot lattice can stay tonally tied
  /// to the live line while the dashed marker reads as a neutral
  /// axis-style tick.
  final Color dashColor;

  /// Price the period opened at — used to anchor the horizontal
  /// dashed reference line.
  final double openPrice;

  /// Whether to draw the dashed open-price reference line at all.
  /// Driven by [SparklineOpenLineCubit]; defaults off in shipping UI.
  final bool showOpenLine;

  /// Distance between adjacent dot centers, in pixels. Sits in the
  /// 5–8 px target band; 6 reads as a deliberate texture without
  /// becoming a wall of dots.
  static const double _spacing = 6.0;

  /// Radius of each dot. Kept sub-pixel so the lattice reads as
  /// texture, not a bullet list.
  static const double _dotRadius = 1.0;

  /// Maximum per-dot alpha, applied at the very top of the chart.
  /// Effective alpha at any dot is `_peakAlpha * (1 - y / height)`.
  /// Tuned so the dots clearly read as the line color rather than a
  /// muted neutral while still leaving headroom for the line itself
  /// to dominate.
  static const double _peakAlpha = 0.7;

  /// Dash / gap lengths for the open-price reference line. Matches
  /// the dashed cadence used elsewhere in the design (the crosshair
  /// uses similar geometry) so multiple dashed chart elements look
  /// like one design family.
  static const double _openDashLength = 4.0;
  static const double _openGapLength = 4.0;

  /// Alpha for the open-price reference line — low enough that the
  /// live line is unambiguously the focal element, high enough to
  /// register as a deliberate marker rather than a stray pixel.
  static const double _openLineAlpha = 0.65;

  /// Stroke width of the open-price reference line. 1 px keeps it
  /// visually quieter than the 2.4 px live line.
  static const double _openLineStroke = 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || size.width <= 0 || size.height <= 0) return;
    final double range = maxY - minY;
    if (range <= 0) return;

    double priceToY(double price) =>
        size.height - (price - minY) / range * size.height;

    // Open-price reference line first so the dot grid paints over it
    // (the dots win any overlap, giving a clean "dotted curtain
    // crossing a dashed marker" effect rather than a continuous line
    // poking through holes).
    if (showOpenLine) {
      final double openY = priceToY(openPrice);
      if (openY >= 0 && openY <= size.height) {
        final Paint openPaint = Paint()
          ..color = dashColor.withValues(alpha: _openLineAlpha)
          ..strokeWidth = _openLineStroke
          ..isAntiAlias = false;
        _drawDashedHorizontal(canvas, openY, size.width, openPaint);
      }
    }

    // Pre-compute pixel-space y for each anchor point — this lets the
    // inner loop just lerp between two neighbors instead of redoing
    // the price-to-pixel mapping per dot column.
    final double xStep = size.width / (points.length - 1);
    final List<double> pxY = <double>[
      for (final PricePoint p in points) priceToY(p.price),
    ];

    double lineYAt(double px) {
      final double t =
          (px / xStep).clamp(0.0, (points.length - 1).toDouble());
      final int i = t.floor();
      final int j = (i + 1).clamp(0, points.length - 1);
      final double f = t - i;
      return pxY[i] * (1 - f) + pxY[j] * f;
    }

    final Paint paint = Paint()..style = PaintingStyle.fill;
    // Start the lattice half-a-cell in from the top-left so the grid
    // visually centers within the chart instead of clinging to the
    // corner. The `<= size.width` / `<= size.height` bounds let the
    // final row/column paint when the chart size lands exactly on a
    // lattice multiple.
    final double startOffset = _spacing / 2;
    for (double x = startOffset; x <= size.width; x += _spacing) {
      final double lineY = lineYAt(x);
      for (double y = startOffset; y <= size.height; y += _spacing) {
        if (y < lineY) continue;
        final double t = (y / size.height).clamp(0.0, 1.0);
        final double alpha = (1.0 - t) * _peakAlpha;
        // Cheap cull — anything below 1% alpha is invisible but still
        // costs a `drawCircle`. The bottom ~10% of the chart hits this
        // and skipping it noticeably reduces draw calls per frame.
        if (alpha <= 0.01) continue;
        paint.color = color.withValues(alpha: alpha);
        canvas.drawCircle(Offset(x, y), _dotRadius, paint);
      }
    }
  }

  /// Strokes a horizontal dashed line at [y] across the full width of
  /// the canvas. Pulled out of [paint] so the dash cadence is defined
  /// in one place — if we ever add other dashed reference markers
  /// (e.g. a "session high" line) they can reuse this helper.
  void _drawDashedHorizontal(
    Canvas canvas,
    double y,
    double width,
    Paint paint,
  ) {
    double x = 0.0;
    while (x < width) {
      final double endX = math.min(x + _openDashLength, width);
      canvas.drawLine(Offset(x, y), Offset(endX, y), paint);
      x += _openDashLength + _openGapLength;
    }
  }

  @override
  bool shouldRepaint(covariant _SparklineDotGridPainter old) =>
      old.points != points ||
      old.color != color ||
      old.dashColor != dashColor ||
      old.minY != minY ||
      old.maxY != maxY ||
      old.openPrice != openPrice ||
      old.showOpenLine != showOpenLine;
}
