import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/crypto_asset.dart';
import '../../../data/models/market_quotes_page.dart';
import '../../../data/repositories/market_repository.dart';
import '../../../data/services/live_price_feed.dart';
import 'markets_event.dart';
import 'markets_state.dart';

/// Page size for paginated market discovery.
const int _marketsPageLimit = 20;

class MarketsBloc extends Bloc<MarketsEvent, MarketsState> {
  MarketsBloc({
    required MarketRepository marketRepository,
    required LivePriceFeed priceFeed,
  }) : _marketRepository = marketRepository,
       _priceFeed = priceFeed,
       super(const MarketsState()) {
    on<MarketsRequested>(_onRequested);
    on<MarketsRefreshed>(_onRefreshed);
    on<MarketsNextPageRequested>(_onNextPageRequested);
    on<MarketsCategoryChanged>(_onCategoryChanged);
    on<MarketsSearchChanged>(_onSearchChanged);
    on<_PricesUpdated>(_onPricesUpdated);

    // Subscribe to the shared feed so a single price tick from
    // anywhere (e.g. the candlestick chart) updates the prices
    // displayed in the markets list in lock-step.
    _feedSub = _priceFeed.watchAll().listen(
      (LivePriceUpdate _) => add(const _PricesUpdated()),
    );
  }

  final MarketRepository _marketRepository;
  final LivePriceFeed _priceFeed;
  late final StreamSubscription<LivePriceUpdate> _feedSub;

  Future<void> _onRequested(
    MarketsRequested event,
    Emitter<MarketsState> emit,
  ) async {
    emit(state.copyWith(status: MarketsStatus.loading, clearError: true));
    try {
      final MarketQuotesPage page = await _marketRepository
          .getMarketQuotesPage(offset: 0, limit: _marketsPageLimit);
      emit(
        state.copyWith(
          status: MarketsStatus.success,
          quotes: page.quotes,
          pageOffset: page.nextOffset,
          hasMore: page.hasMore,
          isLoadingMore: false,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: MarketsStatus.failure,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  Future<void> _onRefreshed(
    MarketsRefreshed event,
    Emitter<MarketsState> emit,
  ) async {
    try {
      final MarketQuotesPage page = await _marketRepository
          .getMarketQuotesPage(offset: 0, limit: _marketsPageLimit);
      emit(
        state.copyWith(
          status: MarketsStatus.success,
          quotes: page.quotes,
          clearError: true,
          pageOffset: page.nextOffset,
          hasMore: page.hasMore,
          isLoadingMore: false,
        ),
      );
    } catch (error) {
      emit(
        state.copyWith(
          status: MarketsStatus.failure,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  Future<void> _onNextPageRequested(
    MarketsNextPageRequested event,
    Emitter<MarketsState> emit,
  ) async {
    // Guard rails: nothing to page if the initial load failed, no
    // more pages, or another page fetch is already in flight.
    if (state.status != MarketsStatus.success) return;
    if (!state.hasMore) return;
    if (state.isLoadingMore) return;

    emit(state.copyWith(isLoadingMore: true));
    try {
      final MarketQuotesPage page = await _marketRepository
          .getMarketQuotesPage(
        offset: state.pageOffset,
        limit: _marketsPageLimit,
      );
      emit(
        state.copyWith(
          quotes: <CryptoQuote>[...state.quotes, ...page.quotes],
          pageOffset: page.nextOffset,
          hasMore: page.hasMore,
          isLoadingMore: false,
        ),
      );
    } catch (error) {
      // Keep the existing successful page set visible; surface the
      // error through `errorMessage` so the screen can show a retry
      // prompt without wiping the list.
      emit(
        state.copyWith(
          isLoadingMore: false,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  void _onCategoryChanged(
    MarketsCategoryChanged event,
    Emitter<MarketsState> emit,
  ) {
    emit(state.copyWith(category: event.category));
  }

  void _onSearchChanged(
    MarketsSearchChanged event,
    Emitter<MarketsState> emit,
  ) {
    emit(state.copyWith(query: event.query));
  }

  void _onPricesUpdated(
    _PricesUpdated event,
    Emitter<MarketsState> emit,
  ) {
    if (state.quotes.isEmpty) return;
    // Each quote carries the warehouse-API-provided 24h anchor; the
    // bloc never re-reads historical data — it just folds the new
    // live price into the cached anchor to recompute change pct.
    //
    // Under the event-based offset model, the cached anchor stays
    // valid across debug dial events: a press dialed in just now
    // does not retroactively shift yesterday's price, so the
    // anchor (= price 24h ago) is unchanged. The change pill
    // therefore reflects the actual jump — exactly the "the
    // price spiked" cue we want for a real-world pump.
    final List<CryptoQuote> updated = state.quotes.map((CryptoQuote q) {
      final double newPrice = _priceFeed.currentPrice(q.asset.symbol);
      final double anchor = q.priceAt24hAgo;
      final double changeAbs = newPrice - anchor;
      final double changePct =
          anchor == 0 ? 0.0 : (changeAbs / anchor) * 100;
      return q.copyWith(
        price: newPrice,
        change24hAbsolute: changeAbs,
        change24hPercent: changePct,
      );
    }).toList();
    emit(state.copyWith(quotes: updated));
  }

  @override
  Future<void> close() async {
    await _feedSub.cancel();
    return super.close();
  }
}

/// Internal: a price tick arrived from the [LivePriceFeed]. Causes
/// `state.quotes` to be remapped against the latest feed prices
/// without going through the API again.
class _PricesUpdated extends MarketsEvent {
  const _PricesUpdated();
}
