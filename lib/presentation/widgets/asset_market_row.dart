import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/crypto_asset.dart';
import '../../design_system/lumina_ui.dart';

/// Markets list row: rank + asset + price + 24h change.
class AssetMarketRow extends StatelessWidget {
  const AssetMarketRow({super.key, required this.quote, this.onTap});

  final CryptoQuote quote;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    final Color changeColor = quote.isPositive
        ? t.colors.feedbackPositive
        : t.colors.feedbackNegative;

    return InkWell(
      onTap: onTap,
      borderRadius: t.radii.mdAll,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: t.spacing.xs,
          vertical: t.spacing.md,
        ),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 24,
              child: Text(
                '${quote.rank}',
                style: t.typography.bodySm.copyWith(
                  color: t.colors.contentTertiary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(width: t.spacing.sm),
            LuminaAvatar(
              color: quote.asset.color,
              label: quote.asset.iconLetter,
            ),
            SizedBox(width: t.spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    quote.asset.name,
                    style: t.typography.bodyLg.copyWith(
                      color: t.colors.contentPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    quote.asset.symbol,
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
                  Formatters.currency(quote.price),
                  style: t.typography.numericSm.copyWith(
                    color: t.colors.contentPrimary,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: t.spacing.xxs),
                Text(
                  Formatters.percent(quote.change24hPercent),
                  style: t.typography.bodySm.copyWith(
                    color: changeColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact row used in the Home screen "Watchlist" cards.
class WatchlistRow extends StatelessWidget {
  const WatchlistRow({super.key, required this.quote, this.onTap});

  final CryptoQuote quote;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    final Color changeColor = quote.isPositive
        ? t.colors.feedbackPositive
        : t.colors.feedbackNegative;
    return LuminaListTile(
      onTap: onTap,
      title: quote.asset.name,
      subtitle: quote.asset.symbol,
      leading: LuminaAvatar(
        color: quote.asset.color,
        label: quote.asset.iconLetter,
      ),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            Formatters.currency(quote.price),
            style: t.typography.numericSm.copyWith(
              color: t.colors.contentPrimary,
              fontSize: 15,
            ),
          ),
          SizedBox(height: t.spacing.xxs),
          Row(
            children: <Widget>[
              Icon(
                quote.isPositive
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 12,
                color: changeColor,
              ),
              const SizedBox(width: 2),
              Text(
                Formatters.percent(quote.change24hPercent, withSign: false),
                style: t.typography.bodySm.copyWith(
                  color: changeColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
