import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/services/sparkline_feed.dart';
import '../../design_system/lumina_ui.dart';

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
class AssetSparkline extends StatelessWidget {
  const AssetSparkline({
    super.key,
    required this.symbol,
    required this.isPositive,
    this.size = const Size(64, 28),
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

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    final SparklineFeed feed = context.read<SparklineFeed>();
    final Color color = isPositive
        ? t.colors.chartCandleBullish
        : t.colors.chartCandleBearish;

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
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Connects the points and fills under the line with a soft
/// gradient, matching the chart's larger sparkline minimap idiom but
/// at row-row scale.
class _AssetSparklinePainter extends CustomPainter {
  _AssetSparklinePainter({required this.points, required this.color});

  final List<double> points;
  final Color color;

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

    // Vertical inset so the line never grazes the row's clipping
    // edges — gives the gradient fill some headroom under the peak.
    const double topPad = 2.0;
    const double bottomPad = 1.0;
    final double drawHeight = size.height - topPad - bottomPad;

    final Path linePath = Path();
    for (int i = 0; i < points.length; i++) {
      final double x = i * stepX;
      final double ratio = flat ? 0.5 : (points[i] - minP) / range;
      final double y = topPad + (drawHeight - ratio * drawHeight);
      if (i == 0) {
        linePath.moveTo(x, y);
      } else {
        linePath.lineTo(x, y);
      }
    }

    final Path fillPath = Path.from(linePath)
      ..lineTo((points.length - 1) * stepX, size.height)
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

    final Paint linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(linePath, linePaint);
  }

  @override
  bool shouldRepaint(covariant _AssetSparklinePainter old) =>
      !identical(old.points, points) || old.color != color;
}
