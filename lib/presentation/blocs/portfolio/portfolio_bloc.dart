import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/clock/clock.dart';
import '../../../data/models/portfolio_holding.dart';
import '../../../data/repositories/portfolio_repository.dart';
import '../../../data/services/live_price_feed.dart';
import 'portfolio_event.dart';
import 'portfolio_state.dart';

class PortfolioBloc extends Bloc<PortfolioEvent, PortfolioState> {
  PortfolioBloc({
    required PortfolioRepository portfolioRepository,
    required LivePriceFeed priceFeed,
    Clock clock = const SystemClock(),
  }) : _portfolioRepository = portfolioRepository,
       _priceFeed = priceFeed,
       _clock = clock,
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
  final Clock _clock;
  late final StreamSubscription<LivePriceUpdate> _feedSub;

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

    final DateTime yesterday =
        _clock.now().subtract(const Duration(hours: 24));

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

    double yesterdayTotal = 0;
    for (final PortfolioHolding h in summary.holdings) {
      yesterdayTotal +=
          h.quantity * _priceFeed.priceAt(h.asset.symbol, yesterday);
    }
    final double changeAbs = newTotal - yesterdayTotal;
    final double changePct =
        yesterdayTotal == 0 ? 0.0 : (changeAbs / yesterdayTotal) * 100;

    emit(
      state.copyWith(
        summary: PortfolioSummary(
          totalValueUsd: newTotal,
          changeTodayUsd: changeAbs,
          changeTodayPercent: changePct,
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
