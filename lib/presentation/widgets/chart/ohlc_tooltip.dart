import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

import '../../../core/utils/formatters.dart';
import '../../../data/models/candle.dart';
import '../../../design_system/lumina_ui.dart';

/// Compact tooltip showing a candle's date plus open / high / low / close /
/// volume. Pure presentation — receives the candle and lays it out.
class OhlcTooltip extends StatelessWidget {
  const OhlcTooltip({super.key, required this.candle});

  final Candle candle;

  static final intl.DateFormat _dateFmt = intl.DateFormat('MMM d, h:mm a');

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    final Color accent = candle.isBullish
        ? t.colors.chartCandleBullish
        : t.colors.chartCandleBearish;
    final TextStyle labelStyle = t.typography.labelSm.copyWith(
      color: t.colors.contentTertiary,
      letterSpacing: 0.6,
    );
    final TextStyle valueStyle = t.typography.numericSm.copyWith(
      color: t.colors.contentPrimary,
    );

    return Material(
      color: t.colors.surfaceRaised.withValues(alpha: 0.95),
      borderRadius: t.radii.smAll,
      elevation: 6,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: t.spacing.md,
          vertical: t.spacing.sm + 2,
        ),
        decoration: BoxDecoration(
          borderRadius: t.radii.smAll,
          border: Border.all(
            color: accent.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(_dateFmt.format(candle.timestamp), style: labelStyle),
            SizedBox(height: t.spacing.xs + 2),
            _Row(label: 'O', value: candle.open, style: valueStyle),
            _Row(
              label: 'H',
              value: candle.high,
              style: valueStyle,
              color: accent,
            ),
            _Row(
              label: 'L',
              value: candle.low,
              style: valueStyle,
              color: accent,
            ),
            _Row(label: 'C', value: candle.close, style: valueStyle),
            SizedBox(height: t.spacing.xs),
            Text(
              'Vol ${Formatters.volume(candle.volume)}',
              style: labelStyle,
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    required this.style,
    this.color,
  });

  final String label;
  final double value;
  final TextStyle style;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 16,
            child: Text(
              label,
              style: style.copyWith(color: t.colors.contentTertiary),
            ),
          ),
          Text(
            Formatters.currency(value),
            style: style.copyWith(color: color ?? style.color),
          ),
        ],
      ),
    );
  }
}
