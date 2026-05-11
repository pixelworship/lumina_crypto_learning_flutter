import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../design_system/lumina_ui.dart';
import '../../blocs/chart/chart_bloc.dart';
import '../../blocs/chart/chart_state.dart';
import '../../blocs/debug/sparkline_open_line_cubit.dart';
import '../../blocs/trade/trade_bloc.dart';

/// Robinhood-style line+gradient minimap pinned to the bottom-left of
/// the chart. Shows the most recent [_closeCap] non-gap candle closes
/// drawn from `state.candles`, so the line shape stays put regardless
/// of how far back the user has extended history.
///
/// Layout is a [Column] with its bottom edge anchored by the parent
/// [Positioned]: the toggle icon sits at the column's bottom slot and
/// therefore never moves, while the chart panel above it tweens its
/// height open/closed via [AnimatedSize].
///
/// The painter renders a fading dot lattice below the line (matching
/// the `PriceSparkline` / `AssetSparkline` idiom across the rest of
/// the app) and, when the app-level [SparklineOpenLineCubit] is on,
/// a dashed reference line at the window's first close.
class ChartMinimap extends StatefulWidget {
  const ChartMinimap({super.key});

  @override
  State<ChartMinimap> createState() => _ChartMinimapState();
}

class _ChartMinimapState extends State<ChartMinimap> {
  /// Number of trailing closes to feed the painter. Bounded so the
  /// minimap stays a snappy "live shape" view independent of how much
  /// historic data the user has loaded.
  static const int _closeCap = 200;
  static const Size _expandedSize = Size(160, 60);

  /// Off by default — the minimap is a power-user affordance, so we
  /// keep the chart card uncluttered until the user explicitly taps
  /// the toggle to surface it.
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Chart panel grows/shrinks with its bottom edge anchored, so
        // the toggle icon below stays put. When collapsed the child is
        // a zero-size box — AnimatedSize tweens the height without
        // translating the icon at all.
        AnimatedSize(
          duration: t.motion.medium,
          curve: t.motion.emphasizedEase,
          alignment: Alignment.bottomLeft,
          child: _visible
              ? Padding(
                  padding: EdgeInsets.only(bottom: t.spacing.xs),
                  child: _buildChartPanel(),
                )
              : const SizedBox.shrink(),
        ),
        _buildToggleButton(context),
      ],
    );
  }

  Widget _buildChartPanel() {
    final LuminaTokens t = context.tokens;
    // The dashed open line is gated by the app-level debug cubit, the
    // same one that controls the dashed line on the home + markets
    // sparklines. Watching here means a toggle from the MainShell FAB
    // (or anywhere else) repaints the minimap on the next frame too.
    final bool showOpenLine =
        context.watch<SparklineOpenLineCubit>().state;
    // Authoritative 24h direction lives on `TradePairSnapshot`
    // (`changePercent` anchored on `priceAt24hAgo`) — the same value
    // the header's change pill displays. Use `context.select` so this
    // widget only rebuilds when the boolean flips, not on every tick
    // that nudges `changePercent` without crossing zero. Null until
    // the trade snapshot resolves; the fallback below handles that
    // warm-up window.
    final bool? isPositive24h = context.select<TradeBloc, bool?>(
      (TradeBloc bloc) => bloc.state.snapshot?.isPositive,
    );
    return BlocSelector<ChartBloc, ChartState, List<double>>(
      selector: (ChartState state) {
        final List<double> closes = <double>[];
        for (int i = state.candles.length - 1;
            i >= 0 && closes.length < _closeCap;
            i--) {
          final c = state.candles[i];
          if (!c.isGap) closes.add(c.close);
        }
        return closes.reversed.toList(growable: false);
      },
      builder: (BuildContext context, List<double> closes) {
        // Prefer the authoritative 24h signal from `TradeBloc`. The
        // minimap's own `closes.last >= closes.first` would only
        // describe the visible window (e.g. ~3 hours of data on the
        // 1m timeframe given the 200-close cap), which can disagree
        // with the actual 24h move — locally up while down for the
        // day, or vice versa. Falls back to the window-local
        // comparison only while the trade snapshot is still loading
        // so the minimap renders something sensible during warm-up.
        final bool isPositive = isPositive24h ??
            (closes.length < 2 ? true : closes.last >= closes.first);
        final Color lineColor = isPositive
            ? t.colors.chartCandleBullish
            : t.colors.chartCandleBearish;
        return Material(
          color: t.colors.surfaceCanvas.withValues(alpha: 0.65),
          borderRadius: t.radii.smAll,
          elevation: 4,
          child: SizedBox(
            width: _expandedSize.width,
            height: _expandedSize.height,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                t.spacing.xs + 2,
                t.spacing.sm,
                t.spacing.xs + 2,
                t.spacing.xs + 2,
              ),
              child: ClipRRect(
                borderRadius: t.radii.xsAll,
                child: CustomPaint(
                  painter: _ChartMinimapPainter(
                    closes: closes,
                    lineColor: lineColor,
                    dashColor: t.colors.contentTertiary,
                    showOpenLine: showOpenLine,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildToggleButton(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return Material(
      color: t.colors.surfaceCanvas.withValues(alpha: 0.65),
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => setState(() => _visible = !_visible),
        child: Padding(
          padding: EdgeInsets.all(t.spacing.sm),
          child: Icon(
            _visible ? Icons.close : Icons.show_chart,
            size: 18,
            color: t.colors.contentSecondary,
          ),
        ),
      ),
    );
  }
}

/// Paints the minimap line plus a fading dot lattice in the area
/// strictly below it, mirroring the treatment used by `PriceSparkline`
/// and `AssetSparkline` across the rest of the app so every line
/// chart in Lumina reads as part of the same visual family.
///
/// The legacy soft-gradient fill is gone — same reasoning as the
/// other sparklines: a same-hue gradient under same-hue dots flattens
/// to "just the gradient", and the dot field already gives the eye a
/// strong sense of below-line volume without needing a tinted wash.
class _ChartMinimapPainter extends CustomPainter {
  _ChartMinimapPainter({
    required this.closes,
    required this.lineColor,
    required this.dashColor,
    required this.showOpenLine,
  });

  final List<double> closes;
  final Color lineColor;

  /// Stroke color for the dashed open-price reference line. Kept
  /// independent of [lineColor] so the dashed marker can use a
  /// neutral gray (an axis-style tick) while the line + dot lattice
  /// stay in the chart's primary hue.
  final Color dashColor;

  /// Whether the dashed open reference line is drawn at all. Driven
  /// by [SparklineOpenLineCubit]; defaults off in shipping UI.
  final bool showOpenLine;

  /// Dot lattice geometry. 5 px / 0.7 px radius matches
  /// `_AssetSparklinePainter` since the minimap's post-padding
  /// drawable area (~140×34) is closer in scale to the markets-row
  /// sparklines than the balance card.
  static const double _dotSpacing = 5.0;
  static const double _dotRadius = 0.7;
  static const double _dotPeakAlpha = 0.65;

  /// Geometry + alpha for the dashed open marker.
  static const double _openDashLength = 3.0;
  static const double _openGapLength = 3.0;
  static const double _openLineAlpha = 0.6;
  static const double _openLineStroke = 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (closes.length < 2 || size.isEmpty) return;

    double minP = closes.first;
    double maxP = closes.first;
    for (final double p in closes) {
      if (p < minP) minP = p;
      if (p > maxP) maxP = p;
    }

    final bool flat = maxP == minP;
    double yFor(double p) {
      if (flat) return size.height / 2;
      final double ratio = (p - minP) / (maxP - minP);
      return size.height - ratio * size.height;
    }

    final double stepX =
        closes.length == 1 ? 0.0 : size.width / (closes.length - 1);

    // Pre-compute pixel y for each close so the inner dot loop just
    // lerps between neighbors instead of redoing the price-to-pixel
    // mapping per dot column.
    final List<double> pxY = <double>[
      for (final double p in closes) yFor(p),
    ];

    // 1. Dashed open marker first (when enabled) so the dot lattice
    //    paints on top of any overlap — same z-order as the other
    //    sparklines.
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

    // 2. Dot lattice strictly below the line. The line itself
    //    paints last so it sits visually on top of the dots.
    _paintDotGrid(canvas, size, pxY, stepX);

    // 3. The line — built as a path so it can render with rounded
    //    joins/caps for a polished look at minimap scale.
    final Path linePath = Path();
    for (int i = 0; i < closes.length; i++) {
      final double x = i * stepX;
      if (i == 0) {
        linePath.moveTo(x, pxY[i]);
      } else {
        linePath.lineTo(x, pxY[i]);
      }
    }
    final Paint linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(linePath, linePaint);
  }

  /// Lays down the line-colored dot lattice in the region strictly
  /// below the polyline. Same mask-and-fade algorithm as
  /// `_AssetSparklinePainter._paintGrid`: linear interpolate the
  /// line's pixel-space y for each column, skip dots above it, and
  /// fade per-row alpha from `_dotPeakAlpha` at the top to 0 at the
  /// bottom.
  void _paintDotGrid(
    Canvas canvas,
    Size size,
    List<double> pxY,
    double stepX,
  ) {
    double lineYAt(double px) {
      if (stepX <= 0) return pxY.first;
      final double t = (px / stepX).clamp(0.0, (closes.length - 1).toDouble());
      final int i = t.floor();
      final int j = (i + 1).clamp(0, closes.length - 1);
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
        if (alpha <= 0.01) continue;
        dotPaint.color = lineColor.withValues(alpha: alpha);
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
  bool shouldRepaint(covariant _ChartMinimapPainter old) =>
      !identical(old.closes, closes) ||
      old.lineColor != lineColor ||
      old.dashColor != dashColor ||
      old.showOpenLine != showOpenLine;
}
