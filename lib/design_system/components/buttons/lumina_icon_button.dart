import 'package:flutter/material.dart';

import '../../tokens/lumina_tokens.dart';

enum LuminaIconButtonVariant { surface, ghost, accent }

/// Square/circular icon-only button used in app bars + toolbars.
class LuminaIconButton extends StatelessWidget {
  const LuminaIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.variant = LuminaIconButtonVariant.surface,
    this.size = 36,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final LuminaIconButtonVariant variant;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;

    final (Color bg, Color fg, Color border) = switch (variant) {
      LuminaIconButtonVariant.surface => (
        t.colors.surfaceRaised,
        t.colors.contentPrimary,
        t.colors.borderDefault,
      ),
      LuminaIconButtonVariant.ghost => (
        Colors.transparent,
        t.colors.contentSecondary,
        Colors.transparent,
      ),
      LuminaIconButtonVariant.accent => (
        t.colors.accentPrimary,
        t.colors.onAccentPrimary,
        t.colors.accentPrimary,
      ),
    };

    final Widget button = Material(
      color: bg,
      shape: CircleBorder(side: BorderSide(color: border)),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: size,
          height: size,
          child: Center(child: Icon(icon, size: size * 0.5, color: fg)),
        ),
      ),
    );

    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}
