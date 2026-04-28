import 'package:flutter/material.dart';

import '../../design_system/lumina_ui.dart';

/// Vertical icon-on-top action button used on the Home dashboard.
///
/// Differs from [LuminaButton] (which is icon-leading) so it earns its place
/// outside the design system as a domain-specific composition.
class _StackedActionButton extends StatelessWidget {
  const _StackedActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    final Color background =
        primary ? t.colors.accentPrimary : t.colors.surfaceRaised;
    final Color foreground =
        primary ? t.colors.onAccentPrimary : t.colors.contentPrimary;
    final Color border =
        primary ? t.colors.accentPrimary : t.colors.borderDefault;

    return Material(
      color: background,
      borderRadius: t.radii.lgAll,
      child: InkWell(
        onTap: onPressed,
        borderRadius: t.radii.lgAll,
        child: Container(
          height: 88,
          decoration: BoxDecoration(
            borderRadius: t.radii.lgAll,
            border: Border.all(color: border),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, color: foreground, size: 24),
              SizedBox(height: t.spacing.sm),
              Text(
                label,
                style: t.typography.labelMd.copyWith(color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Row of three primary actions on the Home screen.
class ActionButtonsRow extends StatelessWidget {
  const ActionButtonsRow({
    super.key,
    required this.onDeposit,
    required this.onWithdraw,
    required this.onSwap,
  });

  final VoidCallback onDeposit;
  final VoidCallback onWithdraw;
  final VoidCallback onSwap;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return Row(
      children: <Widget>[
        Expanded(
          child: _StackedActionButton(
            icon: Icons.south_rounded,
            label: 'DEPOSIT',
            primary: true,
            onPressed: onDeposit,
          ),
        ),
        SizedBox(width: t.spacing.md),
        Expanded(
          child: _StackedActionButton(
            icon: Icons.north_rounded,
            label: 'WITHDRAW',
            onPressed: onWithdraw,
          ),
        ),
        SizedBox(width: t.spacing.md),
        Expanded(
          child: _StackedActionButton(
            icon: Icons.swap_horiz_rounded,
            label: 'SWAP',
            onPressed: onSwap,
          ),
        ),
      ],
    );
  }
}
