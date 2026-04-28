import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/price_point.dart';
import '../../design_system/lumina_ui.dart';

/// Large interactive line chart used on the Trade screen.
class TradeChart extends StatelessWidget {
  const TradeChart({super.key, required this.points, this.height = 240});

  final List<PricePoint> points;
  final double height;

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
    final double padding = (maxY - minY) * 0.1 + 0.001;

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (points.length - 1).toDouble(),
          minY: minY - padding,
          maxY: maxY + padding,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: (maxY - minY) / 4,
            getDrawingHorizontalLine: (double value) => FlLine(
              color: t.colors.chartGrid,
              strokeWidth: 0.6,
              dashArray: const <int>[6, 8],
            ),
          ),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: LineTouchData(
            enabled: true,
            handleBuiltInTouches: true,
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => t.colors.surfaceRaised,
              tooltipRoundedRadius: 8,
              tooltipPadding: EdgeInsets.symmetric(
                horizontal: t.spacing.sm,
                vertical: t.spacing.xs,
              ),
              getTooltipItems: (List<LineBarSpot> spots) {
                return spots.map((LineBarSpot spot) {
                  return LineTooltipItem(
                    Formatters.currency(spot.y),
                    t.typography.bodySm.copyWith(
                      color: t.colors.contentPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                }).toList();
              },
            ),
          ),
          lineBarsData: <LineChartBarData>[
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.3,
              color: t.colors.chartLine,
              barWidth: 2.6,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: t.colors.chartFillGradient,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
