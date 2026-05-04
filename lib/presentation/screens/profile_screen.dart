import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../design_system/lumina_ui.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        t.spacing.xl,
        t.spacing.sm,
        t.spacing.xl,
        t.spacing.xxl,
      ),
      children: <Widget>[
        const _ProfileHero(),
        SizedBox(height: t.spacing.xl),
        const _ThemeToggleCard(),
        SizedBox(height: t.spacing.md),
        for (final _ProfileItem item in _items) ...<Widget>[
          _ProfileTile(item: item),
          SizedBox(height: t.spacing.sm + 2),
        ],
      ],
    );
  }
}

const List<_ProfileItem> _items = <_ProfileItem>[
  _ProfileItem(
    icon: Icons.shield_outlined,
    title: 'Security',
    subtitle: '2FA, biometric login, devices',
  ),
  _ProfileItem(
    icon: Icons.account_balance_wallet_outlined,
    title: 'Wallets',
    subtitle: 'Manage external wallets',
  ),
  _ProfileItem(
    icon: Icons.notifications_none_rounded,
    title: 'Notifications',
    subtitle: 'Price alerts, news',
  ),
  _ProfileItem(
    icon: Icons.help_outline_rounded,
    title: 'Help & Support',
    subtitle: 'FAQ, live chat, contact us',
  ),
  _ProfileItem(
    icon: Icons.info_outline_rounded,
    title: 'About Lumina',
    subtitle: 'Version 1.0.0',
  ),
];

class _ProfileItem {
  const _ProfileItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero();

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return LuminaCard(
      variant: LuminaCardVariant.hero,
      borderRadius: t.radii.xlAll,
      padding: EdgeInsets.all(t.spacing.xl),
      child: Row(
        children: <Widget>[
          LuminaAvatar(
            color: t.colors.accentPrimary,
            label: 'L',
            size: LuminaAvatarSize.lg,
          ),
          SizedBox(width: t.spacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Lumina User',
                  style: t.typography.titleSm.copyWith(
                    color: t.colors.contentPrimary,
                  ),
                ),
                SizedBox(height: t.spacing.xxs),
                Text(
                  'user@lumina.io',
                  style: t.typography.bodySm.copyWith(
                    color: t.colors.contentTertiary,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: t.colors.contentTertiary,
          ),
        ],
      ),
    );
  }
}

/// Live demo of the design system's theme switching: toggle this and the
/// entire app re-themes through the [LuminaTokens] ThemeExtension.
class _ThemeToggleCard extends StatelessWidget {
  const _ThemeToggleCard();

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return BlocBuilder<ThemeModeCubit, ThemeMode>(
      builder: (BuildContext context, ThemeMode mode) {
        final bool isDark = mode == ThemeMode.dark;
        return LuminaCard(
          child: Row(
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: t.colors.surfaceMuted,
                  borderRadius: t.radii.smAll,
                ),
                child: Icon(
                  isDark
                      ? Icons.dark_mode_outlined
                      : Icons.light_mode_outlined,
                  color: t.colors.accentPrimary,
                  size: 18,
                ),
              ),
              SizedBox(width: t.spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Appearance',
                      style: t.typography.titleSm.copyWith(
                        color: t.colors.contentPrimary,
                      ),
                    ),
                    SizedBox(height: t.spacing.xxs),
                    Text(
                      isDark ? 'Dark mode' : 'Light mode',
                      style: t.typography.bodySm.copyWith(
                        color: t.colors.contentTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: isDark,
                activeThumbColor: t.colors.accentPrimary,
                onChanged: (_) => context.read<ThemeModeCubit>().toggle(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({required this.item});

  final _ProfileItem item;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return LuminaCard(
      padding: EdgeInsets.zero,
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${item.title} (mocked)')),
        );
      },
      child: LuminaListTile(
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: t.colors.surfaceMuted,
            borderRadius: t.radii.smAll,
          ),
          child: Icon(item.icon, color: t.colors.accentPrimary, size: 18),
        ),
        title: item.title,
        subtitle: item.subtitle,
        trailing: Icon(
          Icons.chevron_right_rounded,
          color: t.colors.contentTertiary,
        ),
      ),
    );
  }
}
