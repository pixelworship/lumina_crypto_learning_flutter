import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/services/sparkline_feed.dart';
import '../../design_system/lumina_ui.dart';
import '../blocs/debug/sparkline_open_line_cubit.dart';

/// Tiny live sparkline rendered next to the price in markets +
/// watchlist rows.
///
/// Reads its data directly from a [SparklineFeed] keyed by [symbol]
/// — *not* through a bloc. The feed publishes a fresh immutable
/// [SparklineSnapshot] whenever new data arrives, so a
/// `ValueListenable` wired into [ValueListenableBuilder] is the
/// cheapest path between "price tick fired" and "this row repainted".
///
/// While the warehouse api seed-fetch is still in flight the widget
/// renders a [LuminaSkeleton] shimmer of the exact same footprint
/// as the painted polyline — so the row's column-width never jumps
/// on hydration. After the response resolves the polyline takes
/// over and live ticks animate it in place.
///
/// Wrapped in a [RepaintBoundary] so the sparkline's frame-rate
/// repaint never invalidates surrounding text widgets, and so a
/// list-level rebuild (scrolling, page-load) never triggers an
/// unnecessary sparkline repaint.
///
/// When [showGrid] is true (default), the area under the line is
/// rendered as a fading dot lattice instead of a soft gradient and a
/// dashed horizontal "open" reference line is drawn at the snapshot's
/// first value. This matches `PriceSparkline`'s grid treatment so
/// every sparkline in the app reads the same way.
class AssetSparkline extends StatelessWidget {
  const AssetSparkline({
    super.key,
    required this.symbol,
    required this.isPositive,
    this.size = const Size(64, 28),
    this.showGrid = true,
  });

  final String symbol;

  /// Whether the asset's 24h change is positive — drives the line +
  /// gradient color so the sparkline visually agrees with the delta
  /// arrow rendered next to it.
  final bool isPositive;

  /// Fixed render size. Kept narrow (64×28 by default) so it can
  /// nestle between the asset name column and the price column on a
  /// phone-width markets list.
  final Size size;

  /// When true, paints the dot-grid + open-price dashed line treatment
  /// in place of the legacy below-line gradient. See class docs.
  final bool showGrid;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    final SparklineFeed feed = context.read<SparklineFeed>();
    final Color color = isPositive
        ? t.colors.chartCandleBullish
        : t.colors.chartCandleBearish;
    // Shared with `PriceSparkline` — the dashed open marker is hidden
    // by default and only flips on while the debug FAB toggle is
    // active. Watching from inside the builder means a single FAB tap
    // repaints every visible sparkline (markets list + watchlist)
    // simultaneously.
    final bool showOpenLine = context.watch<SparklineOpenLineCubit>().state;

    return RepaintBoundary(
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: ValueListenableBuilder<SparklineSnapshot>(
          valueListenable: feed.watch(symbol),
          builder: (
            BuildContext context,
            SparklineSnapshot snapshot,
            Widget? _,
          ) {
            if (snapshot.isLoading) {
              return LuminaSkeleton(
                width: size.width,
                height: size.height,
                // Tighter than the global small radius so it reads
                // as "where the line goes" rather than a button.
                borderRadius:
                    const BorderRadius.all(Radius.circular(4)),
              );
            }
            return CustomPaint(
              size: size,
              painter: _AssetSparklinePainter(
                points: snapshot.values,
                color: color,
                showGrid: showGrid,
                showOpenLine: showOpenLine,
                // Neutral gray for the dashed open marker so it
                // reads as an axis-style reference rather than
                // another stroke in the same red/green family as
                // the live line.
                dashColor: t.colors.contentTertiary,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Connects the points and renders the area under the line as either
/// a soft gradient (legacy) or a fading dot lattice + dashed open
/// reference line (when `showGrid` is true), matching the chart's
/// larger sparkline minimap idiom but at row-row scale.
class _AssetSparklinePainter extends CustomPainter {
  _AssetSparklinePainter({
    required this.points,
    required this.color,
    required this.showGrid,
    required this.dashColor,
    required this.showOpenLine,
  });

  final List<double> points;
  final Color color;
  final bool showGrid;

  /// Stroke color for the dashed open-price reference line. Kept
  /// independent of [color] so the dashed marker can use a neutral
  /// gray while the line + dot lattice stay in the asset's
  /// up/down hue.
  final Color dashColor;

  /// Whether to draw the dashed open-price marker. Driven by the
  /// app-level [SparklineOpenLineCubit]; defaults off in shipping UI.
  final bool showOpenLine;

  /// Vertical inset around the polyline so it never grazes the row's
  /// clipping edges and the gradient fill (when used) gets headroom
  /// under the peak.
  static const double _topPad = 2.0;
  static const double _bottomPad = 1.0;

  /// Dot lattice geometry. Tighter than `PriceSparkline`'s 6 px grid
  /// because we have ~28 px of height to play with — 5 px gives 5–6
  /// lattice rows and 0.7 px radius keeps each dot from dominating
  /// the small canvas.
  static const double _dotSpacing = 5.0;
  static const double _dotRadius = 0.7;

  /// Per-dot peak alpha, applied at the top of the canvas. Effective
  /// alpha at any row is `_dotPeakAlpha * (1 - y / height)` so the
  /// lattice fades to fully transparent at the bottom edge.
  static const double _dotPeakAlpha = 0.65;

  /// Geometry + alpha for the dashed open-price reference line.
  static const double _openDashLength = 3.0;
  static const double _openGapLength = 3.0;
  static const double _openLineAlpha = 0.6;
  static const double _openLineStroke = 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || size.isEmpty) return;

    double minP = points.first;
    double maxP = points.first;
    for (final double p in points) {
      if (p < minP) minP = p;
      if (p > maxP) maxP = p;
    }
    final bool flat = maxP == minP;
    final double range = flat ? 1.0 : (maxP - minP);
    final double stepX = size.width / (points.length - 1);
    final double drawHeight = size.height - _topPad - _bottomPad;

    double priceToY(double p) {
      final double ratio = flat ? 0.5 : (p - minP) / range;
      return _topPad + (drawHeight - ratio * drawHeight);
    }

    // Build the polyline path used for both the visible stroke and
    // (when grid is off) the gradient fill.
    final Path linePath = Path();
    final List<double> pxY = <double>[
      for (int i = 0; i < points.length; i++) priceToY(points[i]),
    ];
    for (int i = 0; i < points.length; i++) {
      final double x = i * stepX;
      if (i == 0) {
        linePath.moveTo(x, pxY[i]);
      } else {
        linePath.lineTo(x, pxY[i]);
      }
    }

    if (showGrid) {
      _paintGrid(canvas, size, pxY, stepX);
    } else {
      _paintGradientFill(canvas, size, linePath);
    }

    final Paint linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(linePath, linePaint);
  }

  /// Closes the polyline down to the bottom-left and bottom-right
  /// corners and fills it with a vertical line-color gradient. Legacy
  /// rendering kept behind `showGrid: false`.
  void _paintGradientFill(Canvas canvas, Size size, Path linePath) {
    final Path fillPath = Path.from(linePath)
      ..lineTo((points.length - 1) * (size.width / (points.length - 1)),
          size.height)
      ..lineTo(0, size.height)
      ..close();

    final Paint fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          color.withValues(alpha: 0.30),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fillPath, fillPaint);
  }

  /// Paints the open-price dashed reference line plus a fading dot
  /// lattice below the polyline. Order matters: the dashed line goes
  /// down first so the lattice paints on top of any overlap, giving
  /// a "dotted curtain crossing a dashed marker" look rather than a
  /// dashed line poking through holes in the dot field.
  void _paintGrid(
    Canvas canvas,
    Size size,
    List<double> pxY,
    double stepX,
  ) {
    if (showOpenLine) {
      final double openY = pxY.first;
      if (openY >= 0 && openY <= size.height) {
        final Paint openPaint = Paint()
          ..color = dashColor.withValues(alpha: _openLineAlpha)
          ..strokeWidth = _openLineStroke
          ..isAntiAlias = false;
        _drawDashedHorizontal(canvas, openY, size.width, openPaint);
      }
    }

    double lineYAt(double px) {
      final double t = (px / stepX).clamp(0.0, (points.length - 1).toDouble());
      final int i = t.floor();
      final int j = (i + 1).clamp(0, points.length - 1);
      final double f = t - i;
      return pxY[i] * (1 - f) + pxY[j] * f;
    }

    final Paint dotPaint = Paint()..style = PaintingStyle.fill;
    // Half-cell offset so the lattice visually centers within the
    // canvas instead of clinging to the top-left corner.
    final double startOffset = _dotSpacing / 2;
    for (double x = startOffset; x <= size.width; x += _dotSpacing) {
      final double curveY = lineYAt(x);
      for (double y = startOffset; y <= size.height; y += _dotSpacing) {
        if (y < curveY) continue;
        final double t = (y / size.height).clamp(0.0, 1.0);
        final double alpha = (1.0 - t) * _dotPeakAlpha;
        // Skip dots whose alpha is below 1% — the bottom rows hit
        // this and the cull noticeably shrinks per-frame draw
        // calls when there are dozens of these in a list.
        if (alpha <= 0.01) continue;
        dotPaint.color = color.withValues(alpha: alpha);
        canvas.drawCircle(Offset(x, y), _dotRadius, dotPaint);
      }
    }
  }

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
  bool shouldRepaint(covariant _AssetSparklinePainter old) =>
      !identical(old.points, points) ||
      old.color != color ||
      old.dashColor != dashColor ||
      old.showGrid != showGrid ||
      old.showOpenLine != showOpenLine;
}
