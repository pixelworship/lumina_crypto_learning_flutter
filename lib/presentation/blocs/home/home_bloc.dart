import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/clock/clock.dart';
import '../../../data/models/balance_summary.dart';
import '../../../data/models/crypto_asset.dart';
import '../../../data/models/portfolio_holding.dart';
import '../../../data/repositories/market_repository.dart';
import '../../../data/repositories/portfolio_repository.dart';
import '../../../data/services/live_price_feed.dart';
import 'home_event.dart';
import 'home_state.dart';

class HomeBloc extends Bloc<HomeEvent, HomeState> {
  HomeBloc({
    required PortfolioRepository portfolioRepository,
    required MarketRepository marketRepository,
    required LivePriceFeed priceFeed,
    Clock clock = const SystemClock(),
  }) : _portfolioRepository = portfolioRepository,
       _marketRepository = marketRepository,
       _priceFeed = priceFeed,
       _clock = clock,
       super(const HomeState()) {
    on<HomeRequested>(_onRequested);
    on<HomeRefreshed>(_onRefreshed);
    on<HomeQuickActionTriggered>(_onQuickAction);
    on<_PricesUpdated>(_onPricesUpdated);

    _feedSub = _priceFeed.watchAll().listen(
      (LivePriceUpdate _) => add(const _PricesUpdated()),
    );
  }

  final PortfolioRepository _portfolioRepository;
  final MarketRepository _marketRepository;
  final LivePriceFeed _priceFeed;
  final Clock _clock;
  late final StreamSubscription<LivePriceUpdate> _feedSub;

  /// Cached holdings used to recompute the balance card live on each
  /// price tick without needing to round-trip through the api.
  List<PortfolioHolding> _holdings = const <PortfolioHolding>[];

  Future<void> _onRequested(
    HomeRequested event,
    Emitter<HomeState> emit,
  ) async {
    emit(state.copyWith(status: HomeStatus.loading, clearError: true));
    await _load(emit);
  }

  Future<void> _onRefreshed(
    HomeRefreshed event,
    Emitter<HomeState> emit,
  ) async {
    await _load(emit);
  }

  Future<void> _load(Emitter<HomeState> emit) async {
    try {
      final List<Object> results = await Future.wait<Object>(<Future<Object>>[
        _portfolioRepository.getBalanceSummary(),
        _portfolioRepository.getPortfolio(),
        _marketRepository.getWatchlist(),
      ]);
      _holdings = (results[1] as PortfolioSummary).holdings;
      emit(
        state.copyWith(
          status: HomeStatus.success,
          balance: results[0] as BalanceSummary,
          watchlist: results[2] as List<CryptoQuote>,
          clearError: true,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: HomeStatus.failure,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  Future<void> _onQuickAction(
    HomeQuickActionTriggered event,
    Emitter<HomeState> emit,
  ) async {
    switch (event.action) {
      case HomeQuickAction.deposit:
        await _portfolioRepository.deposit(0);
        break;
      case HomeQuickAction.withdraw:
        await _portfolioRepository.withdraw(0);
        break;
      case HomeQuickAction.swap:
        break;
    }
  }

  void _onPricesUpdated(
    _PricesUpdated event,
    Emitter<HomeState> emit,
  ) {
    final BalanceSummary? oldBalance = state.balance;
    if (oldBalance == null && state.watchlist.isEmpty) return;

    final DateTime yesterday =
        _clock.now().subtract(const Duration(hours: 24));

    // Recompute the balance card from the cached holdings + the
    // feed's current prices, so the total balance + 24h change track
    // the same data the chart and markets list show.
    BalanceSummary? newBalance = oldBalance;
    if (oldBalance != null && _holdings.isNotEmpty) {
      double newTotal = 0;
      double yesterdayTotal = 0;
      for (final PortfolioHolding h in _holdings) {
        newTotal +=
            h.quantity * _priceFeed.currentPrice(h.asset.symbol);
        yesterdayTotal +=
            h.quantity * _priceFeed.priceAt(h.asset.symbol, yesterday);
      }
      final double changeAbs = newTotal - yesterdayTotal;
      final double changePct = yesterdayTotal == 0
          ? 0.0
          : (changeAbs / yesterdayTotal) * 100;
      newBalance = BalanceSummary(
        totalBalanceUsd: newTotal,
        change24hUsd: changeAbs,
        change24hPercent: changePct,
        // Keep the existing sparkline; refreshing it on every tick
        // would defeat its "trailing 24h" purpose and look jittery.
        sparkline: oldBalance.sparkline,
      );
    }

    final List<CryptoQuote> newWatchlist = state.watchlist.map((CryptoQuote q) {
      final double newPrice = _priceFeed.currentPrice(q.asset.symbol);
      final double yesterdayPrice =
          _priceFeed.priceAt(q.asset.symbol, yesterday);
      final double changeAbs = newPrice - yesterdayPrice;
      final double changePct = yesterdayPrice == 0
          ? 0.0
          : (changeAbs / yesterdayPrice) * 100;
      return q.copyWith(
        price: newPrice,
        change24hAbsolute: changeAbs,
        change24hPercent: changePct,
      );
    }).toList();

    emit(state.copyWith(balance: newBalance, watchlist: newWatchlist));
  }

  @override
  Future<void> close() async {
    await _feedSub.cancel();
    return super.close();
  }
}

class _PricesUpdated extends HomeEvent {
  const _PricesUpdated();
}
