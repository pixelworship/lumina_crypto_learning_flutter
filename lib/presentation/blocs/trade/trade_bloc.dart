import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/clock/clock.dart';
import '../../../core/diagnostics/mrm_trace.dart';
import '../../../data/models/fill.dart';
import '../../../data/models/trade_pair_snapshot.dart';
import '../../../data/repositories/fill_repository.dart';
import '../../../data/repositories/trade_repository.dart';
import '../../../data/services/live_price_feed.dart';
import 'trade_event.dart';
import 'trade_state.dart';

class TradeBloc extends Bloc<TradeEvent, TradeState> {
  TradeBloc({
    required TradeRepository tradeRepository,
    required LivePriceFeed priceFeed,
    required FillRepository fillRepository,
    Clock clock = const SystemClock(),
    String Function()? idGenerator,
  }) : _tradeRepository = tradeRepository,
       _priceFeed = priceFeed,
       _fillRepository = fillRepository,
       _clock = clock,
       _idGenerator = idGenerator ?? _defaultIdGenerator,
       super(const TradeState()) {
    on<TradeRequested>(_onRequested);
    on<TradeRangeChanged>(_onRangeChanged);
    on<TradeRefreshed>(_onRefreshed);
    on<TradePurchaseSubmitted>(_onPurchase);
    on<_PricesUpdated>(_onPricesUpdated);

    _feedSub = _priceFeed.watchAll().listen(
      (LivePriceUpdate _) => add(const _PricesUpdated()),
    );
  }

  final TradeRepository _tradeRepository;
  final LivePriceFeed _priceFeed;
  final FillRepository _fillRepository;
  final Clock _clock;
  final String Function() _idGenerator;
  late final StreamSubscription<LivePriceUpdate> _feedSub;

  Future<void> _onRequested(
    TradeRequested event,
    Emitter<TradeState> emit,
  ) async {
    MrmTrace.mark(20, 'TradeBloc._onRequested', 'symbol=${event.baseSymbol}');
    emit(
      state.copyWith(
        status: TradeStatus.loading,
        baseSymbol: event.baseSymbol,
        quoteSymbol: event.quoteSymbol,
        clearError: true,
      ),
    );
    MrmTrace.mark(21, 'TradeBloc emit loading');
    await _load(emit);
  }

  Future<void> _onRangeChanged(
    TradeRangeChanged event,
    Emitter<TradeState> emit,
  ) async {
    emit(state.copyWith(range: event.range, status: TradeStatus.loading));
    await _load(emit);
  }

  Future<void> _onRefreshed(
    TradeRefreshed event,
    Emitter<TradeState> emit,
  ) async {
    await _load(emit);
  }

  Future<void> _load(Emitter<TradeState> emit) async {
    try {
      MrmTrace.mark(22, 'TradeBloc.getPair await', 'symbol=${state.baseSymbol}');
      final TradePairSnapshot snapshot = await _tradeRepository.getPair(
        baseSymbol: state.baseSymbol,
        quoteSymbol: state.quoteSymbol,
        range: state.range,
      );
      MrmTrace.mark(23, 'TradeBloc.getPair done');
      emit(
        state.copyWith(
          status: TradeStatus.success,
          snapshot: snapshot,
          clearError: true,
        ),
      );
      MrmTrace.mark(24, 'TradeBloc emit success');
    } catch (error) {
      emit(
        state.copyWith(
          status: TradeStatus.failure,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  /// Handles a `Purchase {symbol}` press from `_PurchaseCard`.
  ///
  /// Acceptance is delegated to [TradeRepository.purchase]; on a
  /// truthy result we record a [Fill] anchored at the purchased base
  /// symbol's *current* live price (read from [LivePriceFeed]) so
  /// the fill marker lands on the candle the user actually saw when
  /// they tapped Purchase. A rejected or thrown purchase records no
  /// fill — we don't want phantom markers for failed buys.
  Future<void> _onPurchase(
    TradePurchaseSubmitted event,
    Emitter<TradeState> emit,
  ) async {
    emit(state.copyWith(
      isSubmittingPurchase: true,
      clearPurchaseResult: true,
    ));
    try {
      final bool ok = await _tradeRepository.purchase(
        fromSymbol: event.fromSymbol,
        toSymbol: event.toSymbol,
        amount: event.amount,
      );
      if (ok) {
        final double price = _priceFeed.currentPrice(event.toSymbol);
        // `currentPrice` returns 0 for unknown symbols; we still
        // record the fill in that pathological case (so the user
        // sees their action) but leave the marker at the floor of
        // the chart instead of fabricating a synthetic price.
        await _fillRepository.recordFill(
          Fill(
            id: _idGenerator(),
            symbol: event.toSymbol.toUpperCase(),
            side: FillSide.buy,
            price: price,
            sizeBase: event.amount,
            costQuote: event.amount * price,
            quoteSymbol: event.fromSymbol.toUpperCase(),
            timestamp: _clock.now(),
          ),
        );
      }
      emit(state.copyWith(
        isSubmittingPurchase: false,
        lastPurchaseSucceeded: ok,
      ));
    } catch (error) {
      emit(
        state.copyWith(
          isSubmittingPurchase: false,
          lastPurchaseSucceeded: false,
          errorMessage: error.toString(),
        ),
      );
    }
  }

  /// Refreshes the snapshot's headline price + change pill from the
  /// shared feed on each tick. The bid/ask ladder + price-history
  /// sparkline stay anchored to whatever the last full load produced
  /// — refreshing them every 200ms would be wasteful and visually
  /// jittery.
  ///
  /// The 24h anchor came from the warehouse API on initial fetch;
  /// we never re-read historical data here. Under the event-based
  /// offset model, the cached anchor stays valid across debug dial
  /// events because the offset only takes effect from the dial
  /// timestamp forward — yesterday's price is unchanged. So a
  /// debug pump shows up naturally as a jump in the change pill,
  /// matching the visual step the chart paints.
  void _onPricesUpdated(
    _PricesUpdated event,
    Emitter<TradeState> emit,
  ) {
    final TradePairSnapshot? snapshot = state.snapshot;
    if (snapshot == null) return;

    final String symbol = snapshot.base.symbol;
    final double newPrice = _priceFeed.currentPrice(symbol);
    final double anchor = snapshot.priceAt24hAgo;
    final double changePct =
        anchor == 0 ? 0.0 : ((newPrice - anchor) / anchor) * 100;

    if (newPrice == snapshot.price &&
        changePct == snapshot.changePercent) {
      return;
    }

    emit(
      state.copyWith(
        snapshot: TradePairSnapshot(
          base: snapshot.base,
          quote: snapshot.quote,
          price: newPrice,
          changePercent: changePct,
          priceAt24hAgo: anchor,
          range: snapshot.range,
          priceHistory: snapshot.priceHistory,
          bids: snapshot.bids,
          asks: snapshot.asks,
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

class _PricesUpdated extends TradeEvent {
  const _PricesUpdated();
}

/// Default fill-id minter: epoch-millis + a 6-digit suffix derived
/// from `Object.hashCode`, so two purchases issued in the same
/// millisecond still get distinct ids without dragging in
/// `package:uuid`. The bloc accepts an override so tests can pin
/// deterministic ids.
int _idCounter = 0;
String _defaultIdGenerator() {
  final int now = DateTime.now().microsecondsSinceEpoch;
  final int salt = (++_idCounter) & 0xFFFFFF;
  return 'fill-$now-${salt.toRadixString(36)}';
}
