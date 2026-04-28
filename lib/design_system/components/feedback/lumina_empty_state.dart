import 'package:flutter/material.dart';

import '../../tokens/lumina_tokens.dart';
import '../buttons/lumina_button.dart';

/// "Nothing here yet" view with an icon, copy and optional CTA.
class LuminaEmptyState extends StatelessWidget {
  const LuminaEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return Padding(
      padding: EdgeInsets.all(t.spacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: t.colors.surfaceMuted,
              borderRadius: t.radii.lgAll,
            ),
            child: Icon(icon, color: t.colors.contentTertiary, size: 24),
          ),
          SizedBox(height: t.spacing.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: t.typography.titleSm.copyWith(
              color: t.colors.contentPrimary,
            ),
          ),
          if (message != null) ...<Widget>[
            SizedBox(height: t.spacing.xs),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: t.typography.bodySm.copyWith(
                color: t.colors.contentTertiary,
              ),
            ),
          ],
          if (actionLabel != null) ...<Widget>[
            SizedBox(height: t.spacing.lg),
            LuminaButton.secondary(
              label: actionLabel!,
              onPressed: onAction,
            ),
          ],
        ],
      ),
    );
  }
}
