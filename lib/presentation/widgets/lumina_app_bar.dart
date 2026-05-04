import 'package:flutter/material.dart';

import '../../design_system/lumina_ui.dart';

/// App-level top bar shared across every Lumina screen.
///
/// Composed entirely of design system primitives — the only "non-token" thing
/// here is the brand mark, which stays constant across themes.
class LuminaAppBar extends StatelessWidget implements PreferredSizeWidget {
  const LuminaAppBar({super.key, this.title = 'Lumina Crypto'});

  final String title;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 8);

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return AppBar(
      backgroundColor: t.colors.surfaceCanvas,
      elevation: 0,
      titleSpacing: 0,
      leading: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: t.spacing.lg,
          vertical: t.spacing.sm,
        ),
        child: LuminaIconButton(
          icon: Icons.person_outline,
          onPressed: () {},
          tooltip: 'Profile',
        ),
      ),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: <Color>[
                  t.colors.accentPrimary,
                  t.colors.accentSecondary,
                ],
              ),
            ),
            child: Icon(
              Icons.bolt,
              size: 14,
              color: t.colors.contentInverse,
            ),
          ),
          SizedBox(width: t.spacing.sm),
          Text(
            title,
            style: t.typography.titleSm.copyWith(
              color: t.colors.contentPrimary,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
      actions: <Widget>[
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: t.spacing.lg,
            vertical: t.spacing.sm,
          ),
          child: LuminaIconButton(
            icon: Icons.notifications_none_rounded,
            onPressed: () {},
            tooltip: 'Notifications',
          ),
        ),
      ],
    );
  }
}
