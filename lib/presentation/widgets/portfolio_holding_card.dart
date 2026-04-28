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
    final Color gainColor = holding.isPositive
        ? t.colors.feedbackPositive
        : t.colors.feedbackNegative;
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
                    Formatters.currency(holding.marketValue),
                    style: t.typography.numericSm.copyWith(
                      color: t.colors.contentPrimary,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Cost: ${Formatters.currency(holding.costBasis, showCents: false)}',
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
              Text(
                Formatters.signedCurrency(holding.unrealizedGainUsd),
                style: t.typography.bodyMd.copyWith(
                  color: gainColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(width: t.spacing.sm),
              LuminaChangePill(
                percent: holding.unrealizedGainPercent,
                size: LuminaChangePillSize.sm,
                percentFormatter: (double v) => Formatters.percent(v),
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
