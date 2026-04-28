import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/utils/formatters.dart';
import '../../data/models/trade_pair_snapshot.dart';
import '../../design_system/lumina_ui.dart';
import '../blocs/trade/trade_bloc.dart';
import '../blocs/trade/trade_event.dart';
import '../blocs/trade/trade_state.dart';
import '../widgets/order_book_panel.dart';
import '../widgets/trade_chart.dart';

class TradeScreen extends StatelessWidget {
  const TradeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return BlocConsumer<TradeBloc, TradeState>(
      listenWhen: (TradeState previous, TradeState current) =>
          previous.lastSwapSucceeded != current.lastSwapSucceeded &&
          current.lastSwapSucceeded != null,
      listener: (BuildContext context, TradeState state) {
        final bool ok = state.lastSwapSucceeded ?? false;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(ok ? 'Swap submitted!' : 'Swap failed.')),
          );
      },
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
              t.spacing.xxl,
            ),
            children: <Widget>[
              _PairHeader(snapshot: snapshot),
              SizedBox(height: t.spacing.md),
              LuminaSegmentedControl<ChartRange>(
                options: ChartRange.values,
                selected: state.range,
                labelOf: (ChartRange r) => r.label,
                onChanged: (ChartRange r) =>
                    context.read<TradeBloc>().add(TradeRangeChanged(r)),
              ),
              SizedBox(height: t.spacing.lg),
              LuminaCard(
                padding: EdgeInsets.fromLTRB(
                  t.spacing.md,
                  t.spacing.lg,
                  t.spacing.md,
                  t.spacing.sm,
                ),
                borderRadius: t.radii.xlAll,
                child: AnimatedSwitcher(
                  duration: t.motion.medium,
                  child: state.status == TradeStatus.loading
                      ? const SizedBox(
                          key: ValueKey<String>('loading'),
                          height: 240,
                          child: Center(child: LuminaLoadingIndicator()),
                        )
                      : TradeChart(
                          key: ValueKey<ChartRange>(state.range),
                          points: snapshot.priceHistory,
                        ),
                ),
              ),
              SizedBox(height: t.spacing.lg),
              OrderBookPanel(bids: snapshot.bids, asks: snapshot.asks),
              SizedBox(height: t.spacing.lg),
              _SwapCard(
                base: snapshot.base.symbol,
                quote: snapshot.quote.symbol,
                isLoading: state.isSubmittingSwap,
                onSwap: (double amount) {
                  context.read<TradeBloc>().add(
                        TradeSwapSubmitted(
                          fromSymbol: snapshot.base.symbol,
                          toSymbol: snapshot.quote.symbol,
                          amount: amount,
                        ),
                      );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

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
            Text(
              Formatters.currency(snapshot.price)
                  .replaceAll(r'$', ''),
              style: t.typography.numericLg.copyWith(
                color: t.colors.accentPrimary,
                fontSize: 28,
              ),
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
          ],
        ),
      ],
    );
  }
}

class _SwapCard extends StatefulWidget {
  const _SwapCard({
    required this.base,
    required this.quote,
    required this.isLoading,
    required this.onSwap,
  });

  final String base;
  final String quote;
  final bool isLoading;
  final ValueChanged<double> onSwap;

  @override
  State<_SwapCard> createState() => _SwapCardState();
}

class _SwapCardState extends State<_SwapCard> {
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
            'Swap',
            style: t.typography.titleSm.copyWith(
              color: t.colors.contentPrimary,
            ),
          ),
          SizedBox(height: t.spacing.sm + 2),
          LuminaTextField(
            controller: _controller,
            label: 'Amount',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            suffixText: widget.base,
          ),
          SizedBox(height: t.spacing.md),
          LuminaButton.primary(
            label: 'SWAP ${widget.base} → ${widget.quote}',
            expand: true,
            isLoading: widget.isLoading,
            onPressed: () {
              final double amount = double.tryParse(_controller.text) ?? 0.0;
              widget.onSwap(amount);
            },
          ),
        ],
      ),
    );
  }
}
