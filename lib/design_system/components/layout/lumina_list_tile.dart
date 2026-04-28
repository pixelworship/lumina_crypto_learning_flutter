import 'package:flutter/material.dart';

import '../../tokens/lumina_tokens.dart';

/// Compositional list row: leading slot + title/subtitle column + trailing slot.
///
/// Built for slot composition rather than a 30-prop monolithic widget — pass
/// in [LuminaAvatar], [Icon], [Text], whatever you need. The row handles
/// padding + ripple consistently.
class LuminaListTile extends StatelessWidget {
  const LuminaListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.padding,
    this.dense = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    final EdgeInsetsGeometry pad = padding ??
        EdgeInsets.symmetric(
          horizontal: t.spacing.lg,
          vertical: dense ? t.spacing.md - 2 : t.spacing.md + 2,
        );

    final Widget body = Row(
      children: <Widget>[
        if (leading != null) ...<Widget>[
          leading!,
          SizedBox(width: t.spacing.md),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: t.typography.bodyLg.copyWith(
                  color: t.colors.contentPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: dense ? 14 : 15,
                ),
              ),
              if (subtitle != null) ...<Widget>[
                SizedBox(height: t.spacing.xxs),
                Text(
                  subtitle!,
                  style: t.typography.bodySm.copyWith(
                    color: t.colors.contentTertiary,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...<Widget>[
          SizedBox(width: t.spacing.md),
          trailing!,
        ],
      ],
    );

    if (onTap == null) return Padding(padding: pad, child: body);
    return InkWell(
      onTap: onTap,
      borderRadius: t.radii.lgAll,
      child: Padding(padding: pad, child: body),
    );
  }
}
