import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/diagnostics/mrm_trace.dart';
import '../../data/models/asset_category.dart';
import '../../design_system/lumina_ui.dart';
import '../blocs/markets/markets_bloc.dart';
import '../blocs/markets/markets_event.dart';
import '../blocs/markets/markets_state.dart';
import '../widgets/asset_market_row.dart';
import 'asset_detail_screen.dart';

class MarketsScreen extends StatefulWidget {
  const MarketsScreen({super.key});

  @override
  State<MarketsScreen> createState() => _MarketsScreenState();
}

class _MarketsScreenState extends State<MarketsScreen> {
  late final TextEditingController _controller;
  late final ScrollController _scrollController;

  /// Distance (in px) from the bottom of the list at which we
  /// pre-fetch the next page. Tuned so by the time the trailing
  /// loading indicator becomes visible the request is already in
  /// flight; the user never reaches a hard stop.
  static const double _prefetchThresholdPx = 320;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: context.read<MarketsBloc>().state.query,
    );
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final ScrollPosition pos = _scrollController.position;
    if (pos.pixels < pos.maxScrollExtent - _prefetchThresholdPx) return;
    final MarketsState state = context.read<MarketsBloc>().state;
    if (!state.hasMore) return;
    if (state.isLoadingMore) return;
    if (state.status != MarketsStatus.success) return;
    context.read<MarketsBloc>().add(const MarketsNextPageRequested());
  }

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        t.spacing.xl,
        t.spacing.sm,
        t.spacing.xl,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Market Discovery',
            style: t.typography.titleLg.copyWith(
              color: t.colors.contentPrimary,
            ),
          ),
          SizedBox(height: t.spacing.md),
          LuminaTextField.search(
            controller: _controller,
            hintText: 'Search tokens, pairs, or categories...',
            onChanged: (String value) =>
                context.read<MarketsBloc>().add(MarketsSearchChanged(value)),
          ),
          SizedBox(height: t.spacing.md),
          BlocBuilder<MarketsBloc, MarketsState>(
            buildWhen: (MarketsState previous, MarketsState current) =>
                previous.category != current.category,
            builder: (BuildContext context, MarketsState state) {
              return LuminaChipBar<AssetCategory>(
                options: AssetCategory.values,
                selected: state.category,
                labelOf: (AssetCategory c) => c.label,
                onSelected: (AssetCategory c) => context
                    .read<MarketsBloc>()
                    .add(MarketsCategoryChanged(c)),
              );
            },
          ),
          SizedBox(height: t.spacing.md),
          const _ColumnHeaders(),
          const Divider(height: 1),
          Expanded(
            child: BlocBuilder<MarketsBloc, MarketsState>(
              builder: (BuildContext context, MarketsState state) {
                if (state.status == MarketsStatus.loading &&
                    state.quotes.isEmpty) {
                  return const Center(child: LuminaLoadingIndicator());
                }
                if (state.status == MarketsStatus.failure &&
                    state.quotes.isEmpty) {
                  return LuminaErrorView(
                    message: state.errorMessage ?? 'Failed to load markets.',
                    onRetry: () => context
                        .read<MarketsBloc>()
                        .add(const MarketsRequested()),
                  );
                }
                final List<dynamic> visible = state.visibleQuotes;
                if (visible.isEmpty) {
                  return LuminaEmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'No matching assets',
                    message:
                        'Try a different search term or pick another category.',
                  );
                }
                final bool showFooter =
                    state.isLoadingMore || state.hasMore;
                final int itemCount =
                    visible.length + (showFooter ? 1 : 0);
                return RefreshIndicator(
                  color: t.colors.accentPrimary,
                  backgroundColor: t.colors.surfaceRaised,
                  onRefresh: () async {
                    context
                        .read<MarketsBloc>()
                        .add(const MarketsRefreshed());
                    await context.read<MarketsBloc>().stream.firstWhere(
                          (MarketsState s) =>
                              s.status != MarketsStatus.loading,
                        );
                  },
                  child: ListView.separated(
                    controller: _scrollController,
                    padding: EdgeInsets.only(
                      bottom: t.spacing.xxl,
                      top: t.spacing.xxs,
                    ),
                    itemCount: itemCount,
                    separatorBuilder:
                        (BuildContext context, int index) {
                      // Suppress the divider just before the footer
                      // so the loading indicator floats free of the
                      // list rule.
                      if (showFooter && index == visible.length - 1) {
                        return const SizedBox.shrink();
                      }
                      return const Divider(height: 1);
                    },
                    itemBuilder: (BuildContext context, int index) {
                      if (showFooter && index == visible.length) {
                        return _PaginationFooter(
                          isLoading: state.isLoadingMore,
                        );
                      }
                      final quote = state.visibleQuotes[index];
                      return AssetMarketRow(
                        quote: quote,
                        onTap: () =>
                            _openAsset(context, quote.asset.symbol),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Pushes a brand-new [AssetDetailScreen] route for [symbol]. Each
  /// push spins up its own scoped [TradeBloc] + [ChartBloc] seeded
  /// with the requested symbol, so the detail page is always a fresh,
  /// isolated experience — no leftover state from the previously
  /// viewed asset.
  void _openAsset(BuildContext context, String symbol) {
    MrmTrace.start('tap $symbol (markets)');
    MrmTrace.mark(10, 'markets._openAsset', 'symbol=$symbol');
    Navigator.of(context).push(AssetDetailScreen.route(symbol));
    MrmTrace.mark(11, 'AssetDetailScreen pushed');
  }
}

/// Trailing list item rendered while paginated quotes are in flight.
/// Stays mounted (with reduced height) when idle so the auto-prefetch
/// has a stable scroll target — flickering it in/out on every page
/// would cause the scroll metrics to jump.
class _PaginationFooter extends StatelessWidget {
  const _PaginationFooter({required this.isLoading});

  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: t.spacing.lg),
      child: Center(
        child: isLoading
            ? const LuminaLoadingIndicator()
            : SizedBox(height: t.spacing.lg),
      ),
    );
  }
}

class _ColumnHeaders extends StatelessWidget {
  const _ColumnHeaders();

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    final TextStyle style = t.typography.labelMd.copyWith(
      color: t.colors.contentTertiary,
    );
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: t.spacing.xs,
        vertical: t.spacing.xs + 2,
      ),
      child: Row(
        children: <Widget>[
          SizedBox(width: 24, child: Text('#', style: style)),
          SizedBox(width: t.spacing.sm),
          Expanded(child: Text('ASSET', style: style)),
          Text('PRICE', style: style),
        ],
      ),
    );
  }
}
