import 'package:flutter/material.dart';

import '../../tokens/lumina_tokens.dart';

enum LuminaCardVariant {
  /// Filled card with a subtle border. The default.
  surface,

  /// Subtler treatment — same fill, no border.
  flat,

  /// Hero card — uses the brand gradient + thin border.
  hero,

  /// Negative-space card outlined only by its border.
  outlined,
}

/// Container with consistent radius, padding, fill and border.
///
/// Pass [onTap] to make the card tappable (it'll get an InkWell ripple).
class LuminaCard extends StatelessWidget {
  const LuminaCard({
    super.key,
    required this.child,
    this.variant = LuminaCardVariant.surface,
    this.padding,
    this.onTap,
    this.borderRadius,
  });

  final Widget child;
  final LuminaCardVariant variant;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    final BorderRadius radius = borderRadius ?? t.radii.lgAll;
    final EdgeInsetsGeometry pad = padding ?? EdgeInsets.all(t.spacing.lg);

    final BoxDecoration decoration = switch (variant) {
      LuminaCardVariant.surface => BoxDecoration(
        color: t.colors.surfaceRaised,
        borderRadius: radius,
        border: Border.all(color: t.colors.borderDefault),
      ),
      LuminaCardVariant.flat => BoxDecoration(
        color: t.colors.surfaceRaised,
        borderRadius: radius,
      ),
      LuminaCardVariant.hero => BoxDecoration(
        gradient: t.colors.heroGradient,
        borderRadius: radius,
        border: Border.all(color: t.colors.borderDefault),
      ),
      LuminaCardVariant.outlined => BoxDecoration(
        color: Colors.transparent,
        borderRadius: radius,
        border: Border.all(color: t.colors.borderDefault),
      ),
    };

    final Widget body = Container(
      padding: pad,
      decoration: decoration,
      child: child,
    );

    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: body,
      ),
    );
  }
}
