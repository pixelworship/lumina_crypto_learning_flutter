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
    this.widthTemplate,
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
  /// top of [LuminaTypography.numericSm] (sized to 14 to match the
  /// surrounding body text) when no style is given. The numeric
  /// scale paints in JetBrains Mono so signed values like `+2.40%`
  /// or `-$1,234.56` keep a fixed glyph advance through each tick.
  final TextStyle? style;

  /// Override the default color (positive → feedbackPositive,
  /// negative → feedbackNegative, zero → contentPrimary).
  final Color? color;

  /// Size in logical pixels for the arrow icon.
  final double iconSize;

  /// Horizontal gap between the arrow and the text.
  final double spacing;

  /// Optional width-pinning template applied to the text portion
  /// of the delta. When set, the text lays out at the template's
  /// width regardless of the live [text] — preventing trailing
  /// neighbors (sparklines, row boundaries) from shimmying as the
  /// value crosses a digit-count boundary like `9.99%` →
  /// `12.94%`. Pass the longest unsigned-percent string the source
  /// formatter can produce in this context, e.g. `'9999.99%'`.
  ///
  /// See [LuminaNumericText] for the underlying mechanism.
  final String? widthTemplate;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    final Color resolved = color ??
        (isZero
            ? t.colors.contentPrimary
            : isPositive
                ? t.colors.feedbackPositive
                : t.colors.feedbackNegative);
    // Default to the mono numeric scale so a `+2.40%` chip never
    // shimmies its neighbors when the value changes. Pin fontSize
    // to 14 so we match the body-text size that callers were
    // previously inheriting via `bodySm`.
    final TextStyle base =
        style ?? t.typography.numericSm.copyWith(fontSize: 14);
    final TextStyle textStyle = base.copyWith(
      color: resolved,
      fontWeight: FontWeight.w600,
    );

    // Build the inline `[icon + gap + text]` group. The arrow's
    // footprint is always reserved — even in the zero state, where
    // it paints transparent — so a value flipping between non-zero
    // and zero (e.g. a freshly-loaded change pct settling at 0.00%)
    // doesn't slide its neighbors sideways.
    Widget buildGroup(String labelText) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            isPositive
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded,
            size: iconSize,
            color: isZero ? Colors.transparent : resolved,
          ),
          SizedBox(width: spacing),
          Text(labelText, style: textStyle, maxLines: 1, softWrap: false),
        ],
      );
    }

    if (widthTemplate == null) {
      return buildGroup(text);
    }

    // When width-pinning, reserve the footprint of the entire
    // `[icon + gap + template-text]` group, then right-align the
    // visible `[icon + gap + text]` group within it. Without this,
    // a `LuminaNumericText` only pins the text column — the icon
    // ends up anchored at the start of the reservation, leaving a
    // visible gap between the arrow and the (right-aligned) digits.
    return Stack(
      alignment: Alignment.centerRight,
      children: <Widget>[
        Visibility(
          visible: false,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: buildGroup(widthTemplate!),
        ),
        buildGroup(text),
      ],
    );
  }
}
