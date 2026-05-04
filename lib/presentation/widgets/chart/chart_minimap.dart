import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../design_system/lumina_ui.dart';
import '../../blocs/chart/chart_bloc.dart';
import '../../blocs/chart/chart_state.dart';

/// Robinhood-style line+gradient minimap pinned to the bottom-left of
/// the chart. Shows the most recent [_closeCap] non-gap candle closes
/// drawn from `state.candles`, so the line shape stays put regardless
/// of how far back the user has extended history.
///
/// Layout is a [Column] with its bottom edge anchored by the parent
/// [Positioned]: the toggle icon sits at the column's bottom slot and
/// therefore never moves, while the chart panel above it tweens its
/// height open/closed via [AnimatedSize].
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Chart panel grows/shrinks with its bottom edge anchored, so
        // the toggle icon below stays put. When collapsed the child is
        // a zero-size box — AnimatedSize tweens the height without
        // translating the icon at all.
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomLeft,
          child: _visible
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 4),
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
        return Material(
          color: t.colors.surfaceCanvas.withValues(alpha: 0.65),
          borderRadius: t.radii.smAll,
          elevation: 4,
          child: SizedBox(
            width: _expandedSize.width,
            height: _expandedSize.height,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
              child: ClipRRect(
                borderRadius: t.radii.xsAll,
                child: CustomPaint(
                  painter: _ChartMinimapPainter(
                    closes: closes,
                    lineColor: t.colors.chartCandleBullish,
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
          padding: const EdgeInsets.all(8),
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

class _ChartMinimapPainter extends CustomPainter {
  _ChartMinimapPainter({required this.closes, required this.lineColor});

  final List<double> closes;
  final Color lineColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (closes.length < 2 || size.isEmpty) return;

    double minP = closes.first;
    double maxP = closes.first;
    for (final double p in closes) {
      if (p < minP) minP = p;
      if (p > maxP) maxP = p;
    }

    double yFor(double p, {required bool flat}) {
      if (flat) return size.height / 2;
      final double ratio = (p - minP) / (maxP - minP);
      return size.height - ratio * size.height;
    }

    final bool flat = maxP == minP;
    final double stepX =
        closes.length == 1 ? 0.0 : size.width / (closes.length - 1);

    final Path linePath = Path();
    for (int i = 0; i < closes.length; i++) {
      final double x = i * stepX;
      final double y = yFor(closes[i], flat: flat);
      if (i == 0) {
        linePath.moveTo(x, y);
      } else {
        linePath.lineTo(x, y);
      }
    }

    final Path fillPath = Path.from(linePath)
      ..lineTo((closes.length - 1) * stepX, size.height)
      ..lineTo(0, size.height)
      ..close();

    final Paint fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          lineColor.withValues(alpha: 0.45),
          lineColor.withValues(alpha: 0.0),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fillPath, fillPaint);

    final Paint linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(linePath, linePaint);
  }

  @override
  bool shouldRepaint(covariant _ChartMinimapPainter old) =>
      !identical(old.closes, closes) || old.lineColor != lineColor;
}
