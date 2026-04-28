import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../data/models/price_point.dart';
import '../../design_system/lumina_ui.dart';

/// Compact area-line chart used inside cards (e.g. "Total Balance").
class PriceSparkline extends StatelessWidget {
  const PriceSparkline({
    super.key,
    required this.points,
    this.lineColor,
    this.fillGradient,
    this.height = 90,
    this.showGrid = false,
  });

  final List<PricePoint> points;
  final Color? lineColor;
  final LinearGradient? fillGradient;
  final double height;
  final bool showGrid;

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

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (points.length - 1).toDouble(),
          minY: minY - padding,
          maxY: maxY + padding,
          gridData: FlGridData(
            show: showGrid,
            drawVerticalLine: false,
            horizontalInterval: (maxY - minY) / 4,
            getDrawingHorizontalLine: (double value) => FlLine(
              color: t.colors.chartGrid,
              strokeWidth: 0.5,
              dashArray: const <int>[4, 6],
            ),
          ),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: <LineChartBarData>[
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.32,
              color: lineColor ?? t.colors.chartLine,
              barWidth: 2.4,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: fillGradient ?? t.colors.chartFillGradient,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
