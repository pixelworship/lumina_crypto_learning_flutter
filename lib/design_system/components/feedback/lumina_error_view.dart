import 'package:flutter/material.dart';

import '../../tokens/lumina_tokens.dart';
import '../buttons/lumina_button.dart';

/// Friendly error display with optional retry action.
class LuminaErrorView extends StatelessWidget {
  const LuminaErrorView({
    super.key,
    required this.message,
    this.title = 'Something went wrong',
    this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(t.spacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: t.colors.feedbackNegativeSurface,
                borderRadius: t.radii.lgAll,
              ),
              child: Icon(
                Icons.error_outline_rounded,
                color: t.colors.feedbackNegative,
                size: 26,
              ),
            ),
            SizedBox(height: t.spacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: t.typography.titleSm.copyWith(
                color: t.colors.contentPrimary,
              ),
            ),
            SizedBox(height: t.spacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: t.typography.bodySm.copyWith(
                color: t.colors.contentSecondary,
              ),
            ),
            if (onRetry != null) ...<Widget>[
              SizedBox(height: t.spacing.lg),
              LuminaButton.secondary(label: 'Retry', onPressed: onRetry),
            ],
          ],
        ),
      ),
    );
  }
}
