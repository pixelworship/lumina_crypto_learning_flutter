import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

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
  }) : _portfolioRepository = portfolioRepository,
       _marketRepository = marketRepository,
       _priceFeed = priceFeed,
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
  late final StreamSubscription<LivePriceUpdate> _feedSub;

  /// Cached holdings used to recompute the balance card live on each
  /// price tick without needing to round-trip through the api.
  List<PortfolioHolding> _holdings = const <PortfolioHolding>[];

  /// Per-symbol "baked offset": the debug price offset that was
  /// active when the cached anchor (watchlist quote's
  /// `priceAt24hAgo` or, summed across holdings, the balance's
  /// `valueAt24hAgo`) was fetched. The bloc folds the per-symbol
  /// delta into both anchors on every tick so an "across the board"
  /// dial leaves change pct stable while the absolute prices and
  /// portfolio totals shift in lockstep.
  final Map<String, double> _bakedOffsets = <String, double>{};

  void _captureWatchlistOffsets(Iterable<CryptoQuote> quotes) {
    for (final CryptoQuote q in quotes) {
      _bakedOffsets[q.asset.symbol.toUpperCase()] =
          _priceFeed.priceOffset(q.asset.symbol);
    }
  }

  void _captureHoldingsOffsets(Iterable<PortfolioHolding> holdings) {
    for (final PortfolioHolding h in holdings) {
      _bakedOffsets[h.asset.symbol.toUpperCase()] =
          _priceFeed.priceOffset(h.asset.symbol);
    }
  }

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
      _captureHoldingsOffsets(_holdings);
      _captureWatchlistOffsets(results[2] as List<CryptoQuote>);
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
      case HomeQuickAction.purchase:
        // No-op at the bloc layer — the screen layer translates this
        // into a navigation push to the markets list, where the user
        // picks an asset to purchase from.
        break;
    }
  }

  void _onPricesUpdated(
    _PricesUpdated event,
    Emitter<HomeState> emit,
  ) {
    final BalanceSummary? oldBalance = state.balance;
    if (oldBalance == null && state.watchlist.isEmpty) return;

    // Recompute the balance card from the cached holdings + the
    // feed's current prices, against the warehouse-API-provided
    // 24h-ago anchor on the cached balance summary.
    //
    // For each holding's symbol, fold in the per-symbol delta
    // between the offset baked into the cached anchor and the
    // feed's current offset — that way a debug-driven price spike
    // on, say, BTC bumps both the live total AND the 24h aggregate
    // by `holding.quantity * delta`, leaving the change pct stable.
    BalanceSummary? newBalance = oldBalance;
    if (oldBalance != null && _holdings.isNotEmpty) {
      double newTotal = 0;
      double anchorShift = 0;
      for (final PortfolioHolding h in _holdings) {
        newTotal +=
            h.quantity * _priceFeed.currentPrice(h.asset.symbol);
        final String key = h.asset.symbol.toUpperCase();
        final double currentOffset = _priceFeed.priceOffset(h.asset.symbol);
        final double bakedOffset = _bakedOffsets[key] ?? currentOffset;
        anchorShift += h.quantity * (currentOffset - bakedOffset);
      }
      final double anchor = oldBalance.valueAt24hAgo + anchorShift;
      final double changeAbs = newTotal - anchor;
      final double changePct =
          anchor == 0 ? 0.0 : (changeAbs / anchor) * 100;
      newBalance = BalanceSummary(
        totalBalanceUsd: newTotal,
        change24hUsd: changeAbs,
        change24hPercent: changePct,
        valueAt24hAgo: anchor,
        // Keep the existing sparkline; refreshing it on every tick
        // would defeat its "trailing 24h" purpose and look jittery.
        sparkline: oldBalance.sparkline,
      );
    }

    final List<CryptoQuote> newWatchlist = state.watchlist.map((CryptoQuote q) {
      final String key = q.asset.symbol.toUpperCase();
      final double newPrice = _priceFeed.currentPrice(q.asset.symbol);
      final double currentOffset = _priceFeed.priceOffset(q.asset.symbol);
      final double bakedOffset = _bakedOffsets[key] ?? currentOffset;
      final double anchor = q.priceAt24hAgo + (currentOffset - bakedOffset);
      final double changeAbs = newPrice - anchor;
      final double changePct =
          anchor == 0 ? 0.0 : (changeAbs / anchor) * 100;
      return q.copyWith(
        price: newPrice,
        priceAt24hAgo: anchor,
        change24hAbsolute: changeAbs,
        change24hPercent: changePct,
      );
    }).toList();

    // Persist the latest offset for every symbol the bloc tracks
    // (holdings + watchlist). Both anchors have now absorbed the
    // delta; subsequent ticks compute deltas against this refreshed
    // baseline.
    for (final PortfolioHolding h in _holdings) {
      _bakedOffsets[h.asset.symbol.toUpperCase()] =
          _priceFeed.priceOffset(h.asset.symbol);
    }
    for (final CryptoQuote q in newWatchlist) {
      _bakedOffsets[q.asset.symbol.toUpperCase()] =
          _priceFeed.priceOffset(q.asset.symbol);
    }

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
