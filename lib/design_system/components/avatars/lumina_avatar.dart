import 'package:flutter/material.dart';

import '../../tokens/lumina_tokens.dart';

enum LuminaAvatarSize { xs, sm, md, lg, xl }

/// Circular avatar with a single initial / icon, brand color and soft glow.
///
/// Use this for crypto asset avatars, user avatars, or anywhere a colored
/// initial circle would make sense.
class LuminaAvatar extends StatelessWidget {
  const LuminaAvatar({
    super.key,
    required this.color,
    this.label,
    this.icon,
    this.size = LuminaAvatarSize.md,
    this.glow = true,
  }) : assert(
         label != null || icon != null,
         'LuminaAvatar requires either label or icon',
       );

  final Color color;
  final String? label;
  final IconData? icon;
  final LuminaAvatarSize size;
  final bool glow;

  double get _diameter => switch (size) {
    LuminaAvatarSize.xs => 24,
    LuminaAvatarSize.sm => 32,
    LuminaAvatarSize.md => 40,
    LuminaAvatarSize.lg => 56,
    LuminaAvatarSize.xl => 72,
  };

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;

    final Color secondary = Color.lerp(color, Colors.black, 0.35) ?? color;
    final List<BoxShadow> shadow = glow
        ? <BoxShadow>[
            BoxShadow(
              color: color.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ]
        : t.elevation.none;

    return Container(
      width: _diameter,
      height: _diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[color, secondary],
        ),
        boxShadow: shadow,
      ),
      child: Center(
        child: icon != null
            ? Icon(
                icon,
                color: t.colors.contentPrimary,
                size: _diameter * 0.45,
              )
            : Text(
                label!,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: _diameter * 0.42,
                ),
              ),
      ),
    );
  }
}
