import 'package:flutter/material.dart';

import '../../tokens/lumina_tokens.dart';

enum LuminaChangePillSize { sm, md }

/// Pill displaying a percentage / absolute change with directional color.
class LuminaChangePill extends StatelessWidget {
  const LuminaChangePill({
    super.key,
    required this.percent,
    this.absoluteValue,
    this.absoluteFormatter,
    this.percentFormatter,
    this.suffix,
    this.size = LuminaChangePillSize.md,
  });

  final double percent;
  final double? absoluteValue;

  /// Optional formatters so widgets can decide how to render the numbers
  /// without coupling the design system to your `intl` setup.
  final String Function(double)? absoluteFormatter;
  final String Function(double)? percentFormatter;

  final String? suffix;
  final LuminaChangePillSize size;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    final bool positive = percent >= 0;
    final Color fg = positive
        ? t.colors.feedbackPositive
        : t.colors.feedbackNegative;
    final Color bg = positive
        ? t.colors.feedbackPositiveSurface
        : t.colors.feedbackNegativeSurface;

    // The pill's directional arrow already carries the sign, so
    // every formatter call is given the absolute value and the
    // built-in fallback never prefixes a `+` or `-`. Callers can
    // still pass a signed formatter if they really want one
    // (the .abs() defends against double-rendering the sign).
    final String pctText = percentFormatter?.call(percent.abs()) ??
        '${percent.abs().toStringAsFixed(2)}%';
    final List<String> parts = <String>[];
    if (absoluteValue != null) {
      parts.add(
        absoluteFormatter?.call(absoluteValue!.abs()) ??
            absoluteValue!.abs().toStringAsFixed(2),
      );
    }
    parts.add('($pctText)');
    if (suffix != null) parts.add(suffix!);

    final TextStyle textStyle = (size == LuminaChangePillSize.sm
            ? t.typography.bodySm
            : t.typography.bodySm.copyWith(fontSize: 12))
        .copyWith(color: fg, fontWeight: FontWeight.w600);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: size == LuminaChangePillSize.sm
            ? t.spacing.sm
            : t.spacing.md,
        vertical: size == LuminaChangePillSize.sm
            ? t.spacing.xs
            : t.spacing.xs + 2,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: t.radii.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            positive
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded,
            size: size == LuminaChangePillSize.sm ? 12 : 14,
            color: fg,
          ),
          SizedBox(width: t.spacing.xs),
          Text(parts.join(' '), style: textStyle),
        ],
      ),
    );
  }
}
