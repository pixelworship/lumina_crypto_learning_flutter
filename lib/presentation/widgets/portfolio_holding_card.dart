import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/portfolio_holding.dart';
import '../../design_system/lumina_ui.dart';

/// Detailed portfolio holding card (Portfolio screen "My Assets" section).
class PortfolioHoldingCard extends StatelessWidget {
  const PortfolioHoldingCard({super.key, required this.holding});

  final PortfolioHolding holding;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return LuminaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              LuminaAvatar(
                color: holding.asset.color,
                label: holding.asset.iconLetter,
              ),
              SizedBox(width: t.spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      holding.asset.name,
                      style: t.typography.bodyLg.copyWith(
                        color: t.colors.contentPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      holding.asset.symbol,
                      style: t.typography.bodySm.copyWith(
                        color: t.colors.contentTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    Formatters.compactCurrency(holding.marketValue),
                    style: t.typography.numericSm.copyWith(
                      color: t.colors.contentPrimary,
                      fontSize: 15,
                    ),
                  ),
                  SizedBox(height: t.spacing.xxs),
                  Text(
                    'Cost: ${Formatters.compactCurrency(holding.costBasis)}',
                    style: t.typography.bodySm.copyWith(
                      color: t.colors.contentTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(height: t.spacing.md),
          Row(
            children: <Widget>[
              LuminaDelta(
                isPositive: holding.isPositive,
                isZero: holding.unrealizedGainUsd == 0,
                text: Formatters.compactCurrency(
                  holding.unrealizedGainUsd.abs(),
                ),
                style: t.typography.bodyMd.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(width: t.spacing.sm),
              LuminaChangePill(
                percent: holding.unrealizedGainPercent,
                size: LuminaChangePillSize.sm,
                percentFormatter: (double v) =>
                    Formatters.percent(v, withSign: false),
              ),
              const Spacer(),
              Text(
                '${Formatters.crypto(holding.quantity)} ${holding.asset.symbol}',
                style: t.typography.bodySm.copyWith(
                  color: t.colors.contentTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
