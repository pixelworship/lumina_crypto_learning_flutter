import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/trade_pair_snapshot.dart';
import '../../data/repositories/chart_events_repository.dart';
import '../../data/repositories/fill_repository.dart';
import '../../data/repositories/historical_tick_repository.dart';
import '../../data/repositories/tick_repository.dart';
import '../../data/repositories/trade_repository.dart';
import '../../data/services/live_price_feed.dart';
import '../../design_system/lumina_ui.dart';
import '../blocs/chart/chart_bloc.dart';
import '../blocs/chart/chart_event.dart';
import '../blocs/chart/chart_state.dart';
import '../blocs/trade/trade_bloc.dart';
import '../blocs/trade/trade_event.dart';
import '../blocs/trade/trade_state.dart';
import '../widgets/chart/auto_scale_toggle_button.dart';
import '../widgets/chart/candlestick_chart.dart';
import '../widgets/chart/chart_minimap.dart';
import '../widgets/chart/debug_panel.dart';
import '../widgets/chart/glow_toggle_button.dart';
import '../widgets/chart/no_live_data_indicator.dart';
import '../widgets/chart/price_flash_overlay.dart';
import '../widgets/chart/timeframe_selector.dart';

/// Asset details screen pushed onto the navigation stack from the markets
/// list or watchlist. Each instance is a fresh, isolated experience —
/// it owns its own [TradeBloc] and [ChartBloc] (created inside this
/// widget's [BlocProvider] scope) so two simultaneous detail pages or
/// repeated openings never share live tick state.
///
/// Layout, top to bottom:
///   1. Pair header (label + live price + change pill)
///   2. Toolbar row (auto-scale, glow toggles)
///   3. Timeframe selector (1s ... 1h)
///   4. Candlestick chart card with price-flash overlay, no-live-data
///      indicator, and chart minimap
///   5. Purchase card (buy-only)
///
/// A speed-dial debug panel floats in the bottom-right.
class AssetDetailScreen extends StatelessWidget {
  const AssetDetailScreen({super.key, required this.symbol});

  /// Base symbol (e.g. `BTC`, `ETH`) the detail page should open on.
  /// Drives both [TradeBloc] (for the pair snapshot + purchase card)
  /// and [ChartBloc] (for candle history + live ticks).
  final String symbol;

  /// Convenience helper so call sites can do
  /// `Navigator.of(context).push(AssetDetailScreen.route('BTC'))`
  /// without having to know about the bloc-provider plumbing.
  static Route<void> route(String symbol) {
    return MaterialPageRoute<void>(
      settings: RouteSettings(name: '/asset/$symbol'),
      builder: (BuildContext _) => AssetDetailScreen(symbol: symbol),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Repository providers (price feed, tick repos) live above the
    // navigator at the app root, so each pushed detail page can read
    // them and spin up its own bloc instances seeded with `symbol`.
    return MultiBlocProvider(
      providers: <BlocProvider<dynamic>>[
        BlocProvider<TradeBloc>(
          create: (BuildContext ctx) => TradeBloc(
            tradeRepository: ctx.read<TradeRepository>(),
            priceFeed: ctx.read<LivePriceFeed>(),
            fillRepository: ctx.read<FillRepository>(),
          )..add(TradeRequested(baseSymbol: symbol)),
        ),
        BlocProvider<ChartBloc>(
          create: (BuildContext ctx) => ChartBloc(
            repository: ctx.read<TickRepository>(),
            historicalRepository: ctx.read<HistoricalTickRepository>(),
            fillRepository: ctx.read<FillRepository>(),
            eventsRepository: ctx.read<ChartEventsRepository>(),
            initialSymbol: symbol,
          )..add(ChartStarted(symbol: symbol)),
        ),
      ],
      child: _AssetDetailView(symbol: symbol),
    );
  }
}

/// Internal scaffold + body. Split out from [AssetDetailScreen] so that
/// `context.read<TradeBloc>()` resolves against the route-scoped bloc
/// providers above rather than searching past them.
class _AssetDetailView extends StatelessWidget {
  const _AssetDetailView({required this.symbol});

  final String symbol;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return BlocListener<TradeBloc, TradeState>(
      listenWhen: (TradeState previous, TradeState current) =>
          previous.lastPurchaseSucceeded != current.lastPurchaseSucceeded &&
          current.lastPurchaseSucceeded != null,
      listener: (BuildContext context, TradeState state) {
        final bool ok = state.lastPurchaseSucceeded ?? false;
        final TradePairSnapshot? snapshot = state.snapshot;
        final String message = ok
            ? (snapshot != null
                ? 'Purchased ${snapshot.base.symbol}'
                : 'Purchase submitted!')
            : 'Purchase failed.';
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      },
      child: Scaffold(
        backgroundColor: t.colors.surfaceCanvas,
        appBar: AppBar(
          backgroundColor: t.colors.surfaceCanvas,
          elevation: 0,
          iconTheme: IconThemeData(color: t.colors.contentPrimary),
          title: Text(
            symbol.toUpperCase(),
            style: t.typography.titleSm.copyWith(
              color: t.colors.contentPrimary,
              letterSpacing: 0.4,
            ),
          ),
        ),
        floatingActionButton: const DebugPanel(),
        body: BlocBuilder<TradeBloc, TradeState>(
          builder: (BuildContext context, TradeState state) {
            final TradePairSnapshot? snapshot = state.snapshot;
            if (snapshot == null) {
              return const Center(child: LuminaLoadingIndicator());
            }
            return RefreshIndicator(
              color: t.colors.accentPrimary,
              backgroundColor: t.colors.surfaceRaised,
              onRefresh: () async {
                context.read<TradeBloc>().add(const TradeRefreshed());
                await context.read<TradeBloc>().stream.firstWhere(
                      (TradeState s) => s.status != TradeStatus.loading,
                    );
              },
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  t.spacing.xl,
                  t.spacing.sm,
                  t.spacing.xl,
                  t.spacing.xxxxl + t.spacing.xxxl,
                ),
                children: <Widget>[
                  _PairHeader(snapshot: snapshot),
                  SizedBox(height: t.spacing.md),
                  const TimeframeSelector(),
                  SizedBox(height: t.spacing.lg),
                  LuminaCard(
                    padding: EdgeInsets.zero,
                    borderRadius: t.radii.xlAll,
                    child: ClipRRect(
                      borderRadius: t.radii.xlAll,
                      child: SizedBox(
                        height: 320,
                        // Lava-lamp fills the full rounded card (incl.
                        // corners). Chart elements live inside an inner
                        // Padding so candles, axes, and labels stay
                        // clear of the rounded corner radius.
                        child: PriceFlashOverlay(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: t.spacing.md,
                              vertical: t.spacing.md,
                            ),
                            child: Stack(
                              children: const <Widget>[
                                Positioned.fill(child: CandlestickChart()),
                                Positioned(
                                  top: 0,
                                  left: 0,
                                  right: 0,
                                  child: Center(child: NoLiveDataIndicator()),
                                ),
                                Positioned(
                                  left: 0,
                                  bottom: 24,
                                  child: ChartMinimap(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: t.spacing.lg),
                  _PurchaseCard(
                    base: snapshot.base.symbol,
                    quote: snapshot.quote.symbol,
                    isLoading: state.isSubmittingPurchase,
                    onPurchase: (double amount) {
                      // Buy-only flow: the user pays in `quote`
                      // (e.g. USDT) and receives `base` (e.g. BTC).
                      context.read<TradeBloc>().add(
                            TradePurchaseSubmitted(
                              fromSymbol: snapshot.quote.symbol,
                              toSymbol: snapshot.base.symbol,
                              amount: amount,
                            ),
                          );
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Asset name + live price + 24h change pill, with chart-level
/// toggles (auto-scale, glow) right-aligned on the price row.
///
/// The price tracks `ChartBloc.lastPrice` so it ticks live as new
/// candles arrive. Falls back to the snapshot's price before the
/// first chart tick lands (e.g. while history is loading).
class _PairHeader extends StatelessWidget {
  const _PairHeader({required this.snapshot});

  final TradePairSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              snapshot.pairLabel,
              style: t.typography.titleMd.copyWith(
                color: t.colors.contentPrimary,
              ),
            ),
            SizedBox(width: t.spacing.sm + 2),
            LuminaBadge(label: snapshot.base.name),
          ],
        ),
        SizedBox(height: t.spacing.xxs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            BlocSelector<ChartBloc, ChartState, double?>(
              selector: (ChartState state) => state.lastPrice,
              builder: (BuildContext context, double? lastPrice) {
                final double price = lastPrice ?? snapshot.price;
                return Text(
                  Formatters.compactCurrency(price),
                  style: t.typography.numericLg.copyWith(
                    color: t.colors.accentPrimary,
                    fontSize: 28,
                  ),
                );
              },
            ),
            SizedBox(width: t.spacing.sm),
            Padding(
              padding: EdgeInsets.only(bottom: t.spacing.xs + 2),
              child: LuminaChangePill(
                percent: snapshot.changePercent,
                size: LuminaChangePillSize.sm,
                percentFormatter: (double v) =>
                    Formatters.percent(v, withSign: false),
              ),
            ),
            const Spacer(),
            const AutoScaleToggleButton(),
            SizedBox(width: t.spacing.sm),
            const GlowToggleButton(),
          ],
        ),
      ],
    );
  }
}

/// Buy-only purchase card on the asset detail screen.
///
/// One button → one direction: pay in [quote], receive [base]. The
/// schema is intentionally generic enough that a future Sell button
/// can be added next to this without forking the bloc / repository
/// surface area.
class _PurchaseCard extends StatefulWidget {
  const _PurchaseCard({
    required this.base,
    required this.quote,
    required this.isLoading,
    required this.onPurchase,
  });

  final String base;
  final String quote;
  final bool isLoading;
  final ValueChanged<double> onPurchase;

  @override
  State<_PurchaseCard> createState() => _PurchaseCardState();
}

class _PurchaseCardState extends State<_PurchaseCard> {
  final TextEditingController _controller =
      TextEditingController(text: '0.10');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return LuminaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Buy',
            style: t.typography.titleSm.copyWith(
              color: t.colors.contentPrimary,
            ),
          ),
          SizedBox(height: t.spacing.sm + 2),
          LuminaTextField(
            controller: _controller,
            label: 'Amount in ${widget.base}',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            suffixText: widget.base,
          ),
          SizedBox(height: t.spacing.md),
          LuminaButton.primary(
            label: 'PURCHASE ${widget.base}',
            expand: true,
            isLoading: widget.isLoading,
            onPressed: () {
              final double amount = double.tryParse(_controller.text) ?? 0.0;
              widget.onPurchase(amount);
            },
          ),
        ],
      ),
    );
  }
}
