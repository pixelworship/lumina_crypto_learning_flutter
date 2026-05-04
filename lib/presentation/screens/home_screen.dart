import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/diagnostics/mrm_trace.dart';
import '../../design_system/lumina_ui.dart';
import '../blocs/home/home_bloc.dart';
import '../blocs/home/home_event.dart';
import '../blocs/home/home_state.dart';
import '../blocs/navigation/navigation_cubit.dart';
import '../widgets/action_buttons_row.dart';
import '../widgets/asset_market_row.dart';
import '../widgets/balance_card.dart';
import 'asset_detail_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return BlocBuilder<HomeBloc, HomeState>(
      builder: (BuildContext context, HomeState state) {
        if (state.status == HomeStatus.loading || state.balance == null) {
          return const Center(child: LuminaLoadingIndicator());
        }
        if (state.status == HomeStatus.failure) {
          return LuminaErrorView(
            message: state.errorMessage ?? 'Could not load dashboard.',
            onRetry: () =>
                context.read<HomeBloc>().add(const HomeRequested()),
          );
        }

        return RefreshIndicator(
          color: t.colors.accentPrimary,
          backgroundColor: t.colors.surfaceRaised,
          onRefresh: () async {
            context.read<HomeBloc>().add(const HomeRefreshed());
            await context.read<HomeBloc>().stream.firstWhere(
                  (HomeState s) => s.status != HomeStatus.loading,
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
              BalanceCard(balance: state.balance!),
              SizedBox(height: t.spacing.lg),
              ActionButtonsRow(
                onDeposit: () => _trigger(
                  context,
                  HomeQuickAction.deposit,
                  'Deposit submitted',
                ),
                onWithdraw: () => _trigger(
                  context,
                  HomeQuickAction.withdraw,
                  'Withdrawal submitted',
                ),
                onSwap: () {
                  // The dedicated trade tab is gone — swaps live on
                  // each asset's detail page. Bounce the user to the
                  // markets list so they can pick an asset to swap.
                  context.read<NavigationCubit>().select(AppTab.markets);
                },
              ),
              SizedBox(height: t.spacing.xxl),
              const LuminaSectionHeader(title: 'Watchlist'),
              SizedBox(height: t.spacing.md),
              for (int i = 0; i < state.watchlist.length; i++) ...<Widget>[
                LuminaCard(
                  padding: EdgeInsets.zero,
                  child: WatchlistRow(
                    quote: state.watchlist[i],
                    onTap: () => _openAsset(
                      context,
                      state.watchlist[i].asset.symbol,
                    ),
                  ),
                ),
                if (i != state.watchlist.length - 1)
                  SizedBox(height: t.spacing.sm + 2),
              ],
            ],
          ),
        );
      },
    );
  }

  void _trigger(
    BuildContext context,
    HomeQuickAction action,
    String message,
  ) {
    context.read<HomeBloc>().add(HomeQuickActionTriggered(action));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Pushes a brand-new [AssetDetailScreen] route for [symbol]. Each
  /// push spins up its own scoped [TradeBloc] + [ChartBloc] seeded
  /// with the requested symbol, so the detail page is always a fresh,
  /// isolated experience — no leftover state from the previously
  /// viewed asset.
  void _openAsset(BuildContext context, String symbol) {
    MrmTrace.start('tap $symbol (home)');
    MrmTrace.mark(10, 'home._openAsset', 'symbol=$symbol');
    Navigator.of(context).push(AssetDetailScreen.route(symbol));
    MrmTrace.mark(11, 'AssetDetailScreen pushed');
  }
}
