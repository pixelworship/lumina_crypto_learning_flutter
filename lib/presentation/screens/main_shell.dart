import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../design_system/lumina_ui.dart';
import '../blocs/home/home_bloc.dart';
import '../blocs/home/home_event.dart';
import '../blocs/markets/markets_bloc.dart';
import '../blocs/markets/markets_event.dart';
import '../blocs/navigation/navigation_cubit.dart';
import '../blocs/portfolio/portfolio_bloc.dart';
import '../blocs/portfolio/portfolio_event.dart';
import '../widgets/lumina_app_bar.dart';
import 'home_screen.dart';
import 'markets_screen.dart';
import 'portfolio_screen.dart';
import 'profile_screen.dart';

/// The persistent scaffold around the main tabs.
///
/// We keep all tab screens alive via [IndexedStack] so they preserve scroll
/// position and don't refetch when the user navigates between tabs. The
/// asset detail experience used to be its own tab here (the "Trade" tab);
/// it now lives off-shell and is pushed as a route from the markets and
/// watchlist rows.
class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  @override
  void initState() {
    super.initState();
    final BuildContext ctx = context;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ctx.read<HomeBloc>().add(const HomeRequested());
      ctx.read<MarketsBloc>().add(const MarketsRequested());
      ctx.read<PortfolioBloc>().add(const PortfolioRequested());
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<NavigationCubit, AppTab>(
      builder: (BuildContext context, AppTab tab) {
        return Scaffold(
          appBar: const LuminaAppBar(),
          body: SafeArea(
            child: IndexedStack(
              index: tab.index,
              children: const <Widget>[
                HomeScreen(),
                MarketsScreen(),
                PortfolioScreen(),
                ProfileScreen(),
              ],
            ),
          ),
          bottomNavigationBar: _LuminaBottomNav(
            currentTab: tab,
            onSelected: (AppTab next) =>
                context.read<NavigationCubit>().select(next),
          ),
        );
      },
    );
  }
}

class _LuminaBottomNav extends StatelessWidget {
  const _LuminaBottomNav({
    required this.currentTab,
    required this.onSelected,
  });

  final AppTab currentTab;
  final ValueChanged<AppTab> onSelected;

  static const List<_NavItem> _items = <_NavItem>[
    _NavItem(tab: AppTab.home, icon: Icons.home_rounded, label: 'HOME'),
    _NavItem(
      tab: AppTab.markets,
      icon: Icons.bar_chart_rounded,
      label: 'MARKETS',
    ),
    _NavItem(
      tab: AppTab.portfolio,
      icon: Icons.pie_chart_outline_rounded,
      label: 'PORTFOLIO',
    ),
    _NavItem(
      tab: AppTab.profile,
      icon: Icons.person_outline_rounded,
      label: 'PROFILE',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: t.colors.surfaceRaised,
        border: Border(top: BorderSide(color: t.colors.borderSubtle)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 70,
          child: Row(
            children: <Widget>[
              for (final _NavItem item in _items)
                Expanded(
                  child: _NavTile(
                    item: item,
                    isSelected: item.tab == currentTab,
                    onTap: () => onSelected(item.tab),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  const _NavItem({
    required this.tab,
    required this.icon,
    required this.label,
  });

  final AppTab tab;
  final IconData icon;
  final String label;
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final _NavItem item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    final Color color =
        isSelected ? t.colors.accentPrimary : t.colors.contentTertiary;
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(item.icon, color: color, size: 22),
          SizedBox(height: t.spacing.xs),
          Text(
            item.label,
            style: t.typography.labelSm.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
