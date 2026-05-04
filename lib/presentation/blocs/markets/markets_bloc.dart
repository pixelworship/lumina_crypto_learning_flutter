import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/clock/clock.dart';
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
    Clock clock = const SystemClock(),
  }) : _marketRepository = marketRepository,
       _priceFeed = priceFeed,
       _clock = clock,
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
  final Clock _clock;
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
    final DateTime yesterday =
        _clock.now().subtract(const Duration(hours: 24));
    final List<CryptoQuote> updated = state.quotes.map((CryptoQuote q) {
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
