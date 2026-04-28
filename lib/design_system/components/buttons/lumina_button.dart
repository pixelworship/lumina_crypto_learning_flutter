import 'package:flutter/material.dart';

import '../../tokens/lumina_tokens.dart';

/// Visual style of a [LuminaButton].
enum LuminaButtonVariant {
  /// Filled accent button — the primary CTA on a screen.
  primary,

  /// Outlined button — same shape, secondary visual weight.
  secondary,

  /// Borderless tappable text — least visual weight.
  ghost,

  /// Filled negative button for destructive actions.
  danger,
}

/// Sizing for [LuminaButton]. Drives padding + typography only.
enum LuminaButtonSize { sm, md, lg }

/// The canonical Lumina button.
///
/// Use this everywhere in product surfaces in place of [FilledButton],
/// [OutlinedButton], or [TextButton]. It handles:
///   * variant (primary / secondary / ghost / danger),
///   * size (sm / md / lg),
///   * loading + disabled states,
///   * leading / trailing icons,
///   * full-width layout via [expand].
class LuminaButton extends StatelessWidget {
  const LuminaButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = LuminaButtonVariant.primary,
    this.size = LuminaButtonSize.md,
    this.leadingIcon,
    this.trailingIcon,
    this.isLoading = false,
    this.expand = false,
  });

  /// Convenience: primary CTA.
  const LuminaButton.primary({
    super.key,
    required this.label,
    required this.onPressed,
    this.size = LuminaButtonSize.md,
    this.leadingIcon,
    this.trailingIcon,
    this.isLoading = false,
    this.expand = false,
  }) : variant = LuminaButtonVariant.primary;

  const LuminaButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.size = LuminaButtonSize.md,
    this.leadingIcon,
    this.trailingIcon,
    this.isLoading = false,
    this.expand = false,
  }) : variant = LuminaButtonVariant.secondary;

  const LuminaButton.ghost({
    super.key,
    required this.label,
    required this.onPressed,
    this.size = LuminaButtonSize.md,
    this.leadingIcon,
    this.trailingIcon,
    this.isLoading = false,
    this.expand = false,
  }) : variant = LuminaButtonVariant.ghost;

  const LuminaButton.danger({
    super.key,
    required this.label,
    required this.onPressed,
    this.size = LuminaButtonSize.md,
    this.leadingIcon,
    this.trailingIcon,
    this.isLoading = false,
    this.expand = false,
  }) : variant = LuminaButtonVariant.danger;

  final String label;
  final VoidCallback? onPressed;
  final LuminaButtonVariant variant;
  final LuminaButtonSize size;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final bool isLoading;
  final bool expand;

  bool get _disabled => onPressed == null || isLoading;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    final _ButtonStyle style = _styleFor(t);

    final Widget content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (isLoading) ...<Widget>[
          SizedBox(
            width: style.iconSize,
            height: style.iconSize,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: style.foreground,
            ),
          ),
        ] else ...<Widget>[
          if (leadingIcon != null) ...<Widget>[
            Icon(leadingIcon, size: style.iconSize, color: style.foreground),
            SizedBox(width: t.spacing.xs),
          ],
          Text(
            label,
            style: style.textStyle.copyWith(color: style.foreground),
          ),
          if (trailingIcon != null) ...<Widget>[
            SizedBox(width: t.spacing.xs),
            Icon(trailingIcon, size: style.iconSize, color: style.foreground),
          ],
        ],
      ],
    );

    return Opacity(
      opacity: _disabled && !isLoading ? 0.5 : 1,
      child: Material(
        color: style.background,
        borderRadius: t.radii.lgAll,
        child: InkWell(
          onTap: _disabled ? null : onPressed,
          borderRadius: t.radii.lgAll,
          splashColor: style.foreground.withValues(alpha: 0.1),
          highlightColor: style.foreground.withValues(alpha: 0.05),
          child: Container(
            padding: style.padding,
            decoration: BoxDecoration(
              borderRadius: t.radii.lgAll,
              border: Border.all(color: style.borderColor),
            ),
            child: content,
          ),
        ),
      ),
    );
  }

  _ButtonStyle _styleFor(LuminaTokens t) {
    final EdgeInsets padding = switch (size) {
      LuminaButtonSize.sm => EdgeInsets.symmetric(
        horizontal: t.spacing.md,
        vertical: t.spacing.xs,
      ),
      LuminaButtonSize.md => EdgeInsets.symmetric(
        horizontal: t.spacing.lg,
        vertical: t.spacing.md,
      ),
      LuminaButtonSize.lg => EdgeInsets.symmetric(
        horizontal: t.spacing.xl,
        vertical: t.spacing.lg,
      ),
    };

    final TextStyle textStyle = switch (size) {
      LuminaButtonSize.sm => t.typography.labelMd,
      LuminaButtonSize.md => t.typography.labelLg,
      LuminaButtonSize.lg => t.typography.labelLg.copyWith(fontSize: 14),
    };

    final double iconSize = switch (size) {
      LuminaButtonSize.sm => 14,
      LuminaButtonSize.md => 16,
      LuminaButtonSize.lg => 18,
    };

    return switch (variant) {
      LuminaButtonVariant.primary => _ButtonStyle(
        background: t.colors.accentPrimary,
        foreground: t.colors.onAccentPrimary,
        borderColor: t.colors.accentPrimary,
        padding: padding,
        textStyle: textStyle,
        iconSize: iconSize,
      ),
      LuminaButtonVariant.secondary => _ButtonStyle(
        background: t.colors.surfaceRaised,
        foreground: t.colors.contentPrimary,
        borderColor: t.colors.borderDefault,
        padding: padding,
        textStyle: textStyle,
        iconSize: iconSize,
      ),
      LuminaButtonVariant.ghost => _ButtonStyle(
        background: Colors.transparent,
        foreground: t.colors.accentPrimary,
        borderColor: Colors.transparent,
        padding: padding,
        textStyle: textStyle,
        iconSize: iconSize,
      ),
      LuminaButtonVariant.danger => _ButtonStyle(
        background: t.colors.feedbackNegative,
        foreground: t.colors.contentInverse,
        borderColor: t.colors.feedbackNegative,
        padding: padding,
        textStyle: textStyle,
        iconSize: iconSize,
      ),
    };
  }
}

class _ButtonStyle {
  const _ButtonStyle({
    required this.background,
    required this.foreground,
    required this.borderColor,
    required this.padding,
    required this.textStyle,
    required this.iconSize,
  });

  final Color background;
  final Color foreground;
  final Color borderColor;
  final EdgeInsets padding;
  final TextStyle textStyle;
  final double iconSize;
}
