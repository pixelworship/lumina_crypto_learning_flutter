import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/portfolio_holding.dart';
import '../../design_system/lumina_ui.dart';

/// Donut chart + legend showing portfolio allocation across assets.
class AllocationDonut extends StatelessWidget {
  const AllocationDonut({super.key, required this.holdings});

  final List<PortfolioHolding> holdings;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return Row(
      children: <Widget>[
        SizedBox(
          width: 150,
          height: 150,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              PieChart(
                PieChartData(
                  startDegreeOffset: -90,
                  sectionsSpace: 3,
                  centerSpaceRadius: 46,
                  sections: <PieChartSectionData>[
                    for (final PortfolioHolding h in holdings)
                      PieChartSectionData(
                        value: h.allocationPercent,
                        color: h.asset.color,
                        showTitle: false,
                        radius: 22,
                      ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'Assets',
                    style: t.typography.labelMd.copyWith(
                      color: t.colors.contentTertiary,
                    ),
                  ),
                  Text(
                    '${holdings.length}',
                    style: t.typography.titleLg.copyWith(
                      color: t.colors.contentPrimary,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        SizedBox(width: t.spacing.lg),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (final PortfolioHolding h in holdings)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: t.spacing.xs),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: h.asset.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: t.spacing.sm),
                      Expanded(
                        child: Text(
                          '${h.asset.name} (${h.asset.symbol})',
                          style: t.typography.bodyMd.copyWith(
                            color: t.colors.contentPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        Formatters.percent(
                          h.allocationPercent,
                          withSign: false,
                        ),
                        // Mono so the right-hand percent column
                        // stays in lockstep across legend rows
                        // when allocations rebalance.
                        style: t.typography.numericSm.copyWith(
                          fontSize: 14,
                          color: t.colors.contentSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
