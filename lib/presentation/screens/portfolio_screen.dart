import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../design_system/lumina_ui.dart';
import '../blocs/navigation/navigation_cubit.dart';
import '../blocs/portfolio/portfolio_bloc.dart';
import '../blocs/portfolio/portfolio_event.dart';
import '../blocs/portfolio/portfolio_state.dart';
import '../widgets/allocation_donut.dart';
import '../widgets/balance_card.dart';
import '../widgets/portfolio_holding_card.dart';

class PortfolioScreen extends StatelessWidget {
  const PortfolioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return BlocBuilder<PortfolioBloc, PortfolioState>(
      builder: (BuildContext context, PortfolioState state) {
        if (state.status == PortfolioStatus.loading || state.summary == null) {
          return const Center(child: LuminaLoadingIndicator());
        }
        if (state.status == PortfolioStatus.failure) {
          return LuminaErrorView(
            message: state.errorMessage ?? 'Could not load portfolio.',
            onRetry: () => context
                .read<PortfolioBloc>()
                .add(const PortfolioRequested()),
          );
        }

        final summary = state.summary!;
        return RefreshIndicator(
          color: t.colors.accentPrimary,
          backgroundColor: t.colors.surfaceRaised,
          onRefresh: () async {
            context.read<PortfolioBloc>().add(const PortfolioRefreshed());
            await context.read<PortfolioBloc>().stream.firstWhere(
                  (PortfolioState s) =>
                      s.status != PortfolioStatus.loading,
                );
          },
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              t.spacing.xl,
              t.spacing.sm,
              t.spacing.xl,
              t.spacing.xxl,
            ),
            children: <Widget>[
              ValueCard(
                label: 'TOTAL PORTFOLIO VALUE',
                value: summary.totalValueUsd,
                changePercent: summary.changeTodayPercent,
                changeAbsolute: summary.changeTodayUsd,
                changeSuffix: 'Today',
              ),
              SizedBox(height: t.spacing.xl),
              const LuminaSectionHeader(title: 'Allocation'),
              SizedBox(height: t.spacing.md),
              LuminaCard(
                child: AllocationDonut(holdings: summary.holdings),
              ),
              SizedBox(height: t.spacing.xl),
              LuminaSectionHeader(
                title: 'My Assets',
                actionLabel: 'View All',
                onActionPressed: () =>
                    context.read<NavigationCubit>().select(AppTab.markets),
              ),
              SizedBox(height: t.spacing.md),
              for (int i = 0; i < summary.holdings.length; i++) ...<Widget>[
                PortfolioHoldingCard(holding: summary.holdings[i]),
                if (i != summary.holdings.length - 1)
                  SizedBox(height: t.spacing.md),
              ],
            ],
          ),
        );
      },
    );
  }
}
