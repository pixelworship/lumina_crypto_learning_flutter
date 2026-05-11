import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/balance_summary.dart';
import '../../design_system/lumina_ui.dart';
import 'price_sparkline.dart';

/// Hero "Total Balance" card with sparkline (Home screen).
class BalanceCard extends StatelessWidget {
  const BalanceCard({super.key, required this.balance});

  final BalanceSummary balance;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return LuminaCard(
      variant: LuminaCardVariant.hero,
      padding: EdgeInsets.fromLTRB(
        t.spacing.xl,
        t.spacing.xl,
        t.spacing.xl,
        t.spacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'TOTAL BALANCE',
            style: t.typography.labelMd.copyWith(
              color: t.colors.contentTertiary,
            ),
          ),
          SizedBox(height: t.spacing.xs + 2),
          Text(
            Formatters.compactCurrency(balance.totalBalanceUsd),
            style: t.typography.numericLg.copyWith(
              color: t.colors.contentPrimary,
            ),
          ),
          SizedBox(height: t.spacing.md),
          Row(
            children: <Widget>[
              LuminaChangePill(
                percent: balance.change24hPercent,
                absoluteValue: balance.change24hUsd,
                absoluteFormatter: Formatters.compactCurrency,
                percentFormatter: (double v) =>
                    Formatters.percent(v, withSign: false),
              ),
              SizedBox(width: t.spacing.sm),
              Text(
                '24h',
                style: t.typography.bodySm.copyWith(
                  color: t.colors.contentSecondary,
                ),
              ),
            ],
          ),
          SizedBox(height: t.spacing.sm),
          PriceSparkline(
            points: balance.sparkline,
            // Drive line + dot-grid color from the authoritative 24h
            // change so the sparkline always agrees with the change
            // pill rendered just above (`balance.change24hPercent`).
            isPositive: balance.isPositive,
          ),
        ],
      ),
    );
  }
}

/// Generic value card (used for "Total Portfolio Value" on Portfolio screen).
class ValueCard extends StatelessWidget {
  const ValueCard({
    super.key,
    required this.label,
    required this.value,
    required this.changePercent,
    required this.changeAbsolute,
    this.changeSuffix,
    this.alignment = CrossAxisAlignment.center,
  });

  final String label;
  final double value;
  final double changePercent;
  final double changeAbsolute;
  final String? changeSuffix;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    final bool isCenter = alignment == CrossAxisAlignment.center;
    return LuminaCard(
      variant: LuminaCardVariant.hero,
      padding: EdgeInsets.symmetric(
        horizontal: t.spacing.xl,
        vertical: t.spacing.lg,
      ),
      child: Column(
        crossAxisAlignment: alignment,
        children: <Widget>[
          Text(
            label,
            style: t.typography.labelMd.copyWith(
              color: t.colors.contentTertiary,
            ),
          ),
          SizedBox(height: t.spacing.sm),
          Text(
            Formatters.compactCurrency(value),
            style: t.typography.numericLg.copyWith(
              color: t.colors.accentPrimary,
              fontSize: 28,
            ),
          ),
          SizedBox(height: t.spacing.sm),
          Align(
            alignment: isCenter ? Alignment.center : Alignment.centerLeft,
            child: LuminaChangePill(
              percent: changePercent,
              absoluteValue: changeAbsolute,
              absoluteFormatter: Formatters.compactCurrency,
              percentFormatter: (double v) =>
                  Formatters.percent(v, withSign: false),
              suffix: changeSuffix,
            ),
          ),
        ],
      ),
    );
  }
}
