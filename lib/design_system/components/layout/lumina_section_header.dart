import 'package:flutter/material.dart';

import '../../tokens/lumina_tokens.dart';

/// "Section title + optional trailing action" header.
///
/// Use the slotted [trailing] for full control, or pass [actionLabel] +
/// [onActionPressed] for the standard "View All →" pattern.
class LuminaSectionHeader extends StatelessWidget {
  const LuminaSectionHeader({
    super.key,
    required this.title,
    this.trailing,
    this.actionLabel,
    this.onActionPressed,
  }) : assert(
         trailing == null || actionLabel == null,
         'Provide either `trailing` or `actionLabel`, not both.',
       );

  final String title;
  final Widget? trailing;
  final String? actionLabel;
  final VoidCallback? onActionPressed;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            title,
            style: t.typography.titleMd.copyWith(
              color: t.colors.contentPrimary,
            ),
          ),
        ),
        if (trailing != null)
          trailing!
        else if (actionLabel != null)
          _ViewAllAction(label: actionLabel!, onPressed: onActionPressed),
      ],
    );
  }
}

class _ViewAllAction extends StatelessWidget {
  const _ViewAllAction({required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size(0, 0),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: t.typography.labelLg.copyWith(
              color: t.colors.accentPrimary,
            ),
          ),
          SizedBox(width: t.spacing.xs),
          Icon(
            Icons.arrow_forward_rounded,
            size: 16,
            color: t.colors.accentPrimary,
          ),
        ],
      ),
    );
  }
}
