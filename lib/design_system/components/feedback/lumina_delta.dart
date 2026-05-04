import 'package:flutter/material.dart';

import '../../tokens/lumina_tokens.dart';

/// Inline delta indicator: a colored direction arrow + a text label.
///
/// Replaces the `+`/`-` sign convention with a directional arrow
/// across the app. Use anywhere a signed value (24h change, P&L,
/// debug price offset, etc.) is rendered as a chip-less inline
/// piece of text. For larger emphasized chips with a tinted
/// background, use [LuminaChangePill] instead — both share the same
/// arrow + unsigned-text idiom.
///
/// `isPositive` decides the arrow direction and the color (positive
/// → up + emerald, negative → down + rose). Pass `isZero: true` to
/// suppress the arrow entirely and use [contentPrimary] — useful
/// for "no change" states like a 0% delta or a $0 debug offset.
class LuminaDelta extends StatelessWidget {
  const LuminaDelta({
    super.key,
    required this.isPositive,
    required this.text,
    this.isZero = false,
    this.style,
    this.color,
    this.iconSize = 12,
    this.spacing = 2,
  });

  /// True for an "up" delta (positive change). False for "down"
  /// (negative). Ignored when [isZero] is true.
  final bool isPositive;

  /// True when the value is exactly zero — suppresses the arrow,
  /// uses neutral color, and keeps the chip readable as a settled
  /// "no change" state.
  final bool isZero;

  /// Pre-formatted unsigned label, e.g. `2.40%`, `$1,234.56`,
  /// `$25.00`. The widget never applies its own sign.
  final String text;

  /// Optional text style override. Color comes from [color] (or the
  /// matching feedback token); other style attributes are merged on
  /// top of [LuminaTypography.bodySm] when no style is given.
  final TextStyle? style;

  /// Override the default color (positive → feedbackPositive,
  /// negative → feedbackNegative, zero → contentPrimary).
  final Color? color;

  /// Size in logical pixels for the arrow icon.
  final double iconSize;

  /// Horizontal gap between the arrow and the text.
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    final Color resolved = color ??
        (isZero
            ? t.colors.contentPrimary
            : isPositive
                ? t.colors.feedbackPositive
                : t.colors.feedbackNegative);
    final TextStyle base = style ?? t.typography.bodySm;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (!isZero) ...<Widget>[
          Icon(
            isPositive
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded,
            size: iconSize,
            color: resolved,
          ),
          SizedBox(width: spacing),
        ],
        Text(
          text,
          style: base.copyWith(
            color: resolved,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
