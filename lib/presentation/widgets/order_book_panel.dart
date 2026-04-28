import 'package:flutter/material.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/order_book_entry.dart';
import '../../design_system/lumina_ui.dart';

/// Two-column Bids / Asks order book composed from [LuminaCard].
class OrderBookPanel extends StatelessWidget {
  const OrderBookPanel({
    super.key,
    required this.bids,
    required this.asks,
  });

  final List<OrderBookEntry> bids;
  final List<OrderBookEntry> asks;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: _OrderBookColumn(
            label: 'BIDS',
            entries: bids,
            color: t.colors.feedbackPositive,
          ),
        ),
        SizedBox(width: t.spacing.md),
        Expanded(
          child: _OrderBookColumn(
            label: 'ASKS',
            entries: asks,
            color: t.colors.feedbackNegative,
          ),
        ),
      ],
    );
  }
}

class _OrderBookColumn extends StatelessWidget {
  const _OrderBookColumn({
    required this.label,
    required this.entries,
    required this.color,
  });

  final String label;
  final List<OrderBookEntry> entries;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return LuminaCard(
      padding: EdgeInsets.symmetric(
        horizontal: t.spacing.md + 2,
        vertical: t.spacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: t.typography.labelMd.copyWith(
              color: color.withValues(alpha: 0.7),
            ),
          ),
          SizedBox(height: t.spacing.sm),
          for (final OrderBookEntry entry in entries) ...<Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Expanded(
                  child: Text(
                    Formatters.crypto(entry.price),
                    style: t.typography.numericSm.copyWith(
                      color: color,
                      fontSize: 12,
                    ),
                  ),
                ),
                Text(
                  Formatters.crypto(entry.amount),
                  style: t.typography.numericSm.copyWith(
                    color: t.colors.contentSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            SizedBox(height: t.spacing.xs),
            Container(
              height: 1,
              color: t.colors.borderSubtle.withValues(alpha: 0.5),
            ),
            SizedBox(height: t.spacing.xs),
          ],
        ],
      ),
    );
  }
}
