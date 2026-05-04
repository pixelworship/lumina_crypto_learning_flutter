import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/crypto_asset.dart';
import '../../design_system/lumina_ui.dart';
import 'asset_sparkline.dart';

/// Markets list row: rank + asset + price + 24h change.
class AssetMarketRow extends StatelessWidget {
  const AssetMarketRow({super.key, required this.quote, this.onTap});

  final CryptoQuote quote;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;

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
            AssetSparkline(
              symbol: quote.asset.symbol,
              isPositive: quote.isPositive,
            ),
            SizedBox(width: t.spacing.md),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  Formatters.compactCurrency(quote.price),
                  style: t.typography.numericSm.copyWith(
                    color: t.colors.contentPrimary,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: t.spacing.xxs),
                LuminaDelta(
                  isPositive: quote.isPositive,
                  isZero: quote.change24hPercent == 0,
                  text: Formatters.percent(
                    quote.change24hPercent,
                    withSign: false,
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
    return LuminaListTile(
      onTap: onTap,
      title: quote.asset.name,
      subtitle: quote.asset.symbol,
      leading: LuminaAvatar(
        color: quote.asset.color,
        label: quote.asset.iconLetter,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          AssetSparkline(
            symbol: quote.asset.symbol,
            isPositive: quote.isPositive,
            size: const Size(56, 24),
          ),
          SizedBox(width: t.spacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                Formatters.compactCurrency(quote.price),
                style: t.typography.numericSm.copyWith(
                  color: t.colors.contentPrimary,
                  fontSize: 15,
                ),
              ),
              SizedBox(height: t.spacing.xxs),
              LuminaDelta(
                isPositive: quote.isPositive,
                isZero: quote.change24hPercent == 0,
                text: Formatters.percent(
                  quote.change24hPercent,
                  withSign: false,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
