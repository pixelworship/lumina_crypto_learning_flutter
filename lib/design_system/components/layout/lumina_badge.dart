import 'package:flutter/material.dart';

import '../../tokens/lumina_tokens.dart';

enum LuminaBadgeTone { neutral, info, positive, negative, warning }

/// Compact label used to tag entities (e.g. "Bitcoin" next to a pair name).
class LuminaBadge extends StatelessWidget {
  const LuminaBadge({
    super.key,
    required this.label,
    this.tone = LuminaBadgeTone.neutral,
    this.icon,
  });

  final String label;
  final LuminaBadgeTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;

    final (Color bg, Color fg) = switch (tone) {
      LuminaBadgeTone.neutral => (
        t.colors.surfaceRaised,
        t.colors.contentSecondary,
      ),
      LuminaBadgeTone.info => (
        t.colors.feedbackPositiveSurface,
        t.colors.feedbackInfo,
      ),
      LuminaBadgeTone.positive => (
        t.colors.feedbackPositiveSurface,
        t.colors.feedbackPositive,
      ),
      LuminaBadgeTone.negative => (
        t.colors.feedbackNegativeSurface,
        t.colors.feedbackNegative,
      ),
      LuminaBadgeTone.warning => (
        t.colors.feedbackWarningSurface,
        t.colors.feedbackWarning,
      ),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: t.spacing.sm,
        vertical: t.spacing.xxs + 1,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: t.radii.smAll,
        border: tone == LuminaBadgeTone.neutral
            ? Border.all(color: t.colors.borderDefault)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 11, color: fg),
            SizedBox(width: t.spacing.xs),
          ],
          Text(
            label,
            style: t.typography.labelMd.copyWith(
              color: fg,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}
