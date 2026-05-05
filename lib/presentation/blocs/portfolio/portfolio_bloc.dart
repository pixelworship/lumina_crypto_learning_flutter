import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/portfolio_holding.dart';
import '../../../data/repositories/portfolio_repository.dart';
import '../../../data/services/live_price_feed.dart';
import 'portfolio_event.dart';
import 'portfolio_state.dart';

class PortfolioBloc extends Bloc<PortfolioEvent, PortfolioState> {
  PortfolioBloc({
    required PortfolioRepository portfolioRepository,
    required LivePriceFeed priceFeed,
  }) : _portfolioRepository = portfolioRepository,
       _priceFeed = priceFeed,
       super(const PortfolioState()) {
    on<PortfolioRequested>(_onRequested);
    on<PortfolioRefreshed>(_onRefreshed);
    on<_PricesUpdated>(_onPricesUpdated);

    _feedSub = _priceFeed.watchAll().listen(
      (LivePriceUpdate _) => add(const _PricesUpdated()),
    );
  }

  final PortfolioRepository _portfolioRepository;
  final LivePriceFeed _priceFeed;
  late final StreamSubscription<LivePriceUpdate> _feedSub;

  /// Per-symbol "baked offset": the debug price offset that was
  /// active when the cached portfolio's `totalValueAt24hAgo` was
  /// computed (i.e. when the warehouse api summed
  /// `quantity * (noise(yesterday) + offset)` per holding). On every
  /// live tick the bloc folds the per-symbol delta back into the
  /// aggregate so the 24h pill stays stable while the absolute
  /// total tracks the dialed offset uniformly.
  final Map<String, double> _bakedOffsets = <String, double>{};

  void _captureBakedOffsets(Iterable<PortfolioHolding> holdings) {
    for (final PortfolioHolding h in holdings) {
      _bakedOffsets[h.asset.symbol.toUpperCase()] =
          _priceFeed.priceOffset(h.asset.symbol);
    }
  }

  Future<void> _onRequested(
    PortfolioRequested event,
    Emitter<PortfolioState> emit,
  ) async {
    emit(state.copyWith(status: PortfolioStatus.loading, clearError: true));
    await _load(emit);
  }

  Future<void> _onRefreshed(
    PortfolioRefreshed event,
    Emitter<PortfolioState> emit,
  ) async {
    await _load(emit);
  }

  Future<void> _load(Emitter<PortfolioState> emit) async {
    try {
      final PortfolioSummary summary = await _portfolioRepository
          .getPortfolio();
      _captureBakedOffsets(summary.holdings);
      emit(
        state.copyWith(status: PortfolioStatus.success, summary: summary),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: PortfolioStatus.failure,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  void _onPricesUpdated(
    _PricesUpdated event,
    Emitter<PortfolioState> emit,
  ) {
    final PortfolioSummary? summary = state.summary;
    if (summary == null || summary.holdings.isEmpty) return;

    final List<PortfolioHolding> updatedHoldings =
        summary.holdings.map((PortfolioHolding h) {
      final double newPrice = _priceFeed.currentPrice(h.asset.symbol);
      return PortfolioHolding(
        asset: h.asset,
        quantity: h.quantity,
        currentPrice: newPrice,
        costBasisPerUnit: h.costBasisPerUnit,
        // Allocation gets recomputed below once we know the total.
        allocationPercent: h.allocationPercent,
      );
    }).toList();

    final double newTotal = updatedHoldings.fold<double>(
      0,
      (double sum, PortfolioHolding h) => sum + h.marketValue,
    );

    // Recompute allocations against the new total so the donut chart
    // also tracks the live mix (a 10% pump on BTC nudges the slice).
    final List<PortfolioHolding> rebalanced =
        updatedHoldings.map((PortfolioHolding h) {
      return PortfolioHolding(
        asset: h.asset,
        quantity: h.quantity,
        currentPrice: h.currentPrice,
        costBasisPerUnit: h.costBasisPerUnit,
        allocationPercent:
            newTotal == 0 ? 0 : (h.marketValue / newTotal) * 100,
      );
    }).toList();

    // The 24h-ago aggregate was returned by the warehouse API on
    // initial fetch with a per-holding offset baked in. If the user
    // has dialed the debug offset since, fold the per-symbol delta
    // (× quantity) into the aggregate so the 24h pill matches the
    // chart's "across the board" shift instead of phantom-spiking.
    double anchorShift = 0;
    for (final PortfolioHolding h in summary.holdings) {
      final String key = h.asset.symbol.toUpperCase();
      final double currentOffset = _priceFeed.priceOffset(h.asset.symbol);
      final double bakedOffset = _bakedOffsets[key] ?? currentOffset;
      anchorShift += h.quantity * (currentOffset - bakedOffset);
    }
    final double anchor = summary.totalValueAt24hAgo + anchorShift;
    final double changeAbs = newTotal - anchor;
    final double changePct =
        anchor == 0 ? 0.0 : (changeAbs / anchor) * 100;

    // Persist the latest per-symbol offsets so subsequent ticks
    // compute their delta against this refreshed baseline (the
    // anchor has now absorbed the dial, so the delta resets).
    for (final PortfolioHolding h in summary.holdings) {
      _bakedOffsets[h.asset.symbol.toUpperCase()] =
          _priceFeed.priceOffset(h.asset.symbol);
    }

    emit(
      state.copyWith(
        summary: PortfolioSummary(
          totalValueUsd: newTotal,
          changeTodayUsd: changeAbs,
          changeTodayPercent: changePct,
          totalValueAt24hAgo: anchor,
          holdings: rebalanced,
        ),
      ),
    );
  }

  @override
  Future<void> close() async {
    await _feedSub.cancel();
    return super.close();
  }
}

class _PricesUpdated extends PortfolioEvent {
  const _PricesUpdated();
}
