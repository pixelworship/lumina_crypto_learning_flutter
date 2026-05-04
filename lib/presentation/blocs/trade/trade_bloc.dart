import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/clock/clock.dart';
import '../../../core/diagnostics/mrm_trace.dart';
import '../../../data/models/trade_pair_snapshot.dart';
import '../../../data/repositories/trade_repository.dart';
import '../../../data/services/live_price_feed.dart';
import 'trade_event.dart';
import 'trade_state.dart';

class TradeBloc extends Bloc<TradeEvent, TradeState> {
  TradeBloc({
    required TradeRepository tradeRepository,
    required LivePriceFeed priceFeed,
    Clock clock = const SystemClock(),
  }) : _tradeRepository = tradeRepository,
       _priceFeed = priceFeed,
       _clock = clock,
       super(const TradeState()) {
    on<TradeRequested>(_onRequested);
    on<TradeRangeChanged>(_onRangeChanged);
    on<TradeRefreshed>(_onRefreshed);
    on<TradeSwapSubmitted>(_onSwap);
    on<_PricesUpdated>(_onPricesUpdated);

    _feedSub = _priceFeed.watchAll().listen(
      (LivePriceUpdate _) => add(const _PricesUpdated()),
    );
  }

  final TradeRepository _tradeRepository;
  final LivePriceFeed _priceFeed;
  final Clock _clock;
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

  Future<void> _onSwap(
    TradeSwapSubmitted event,
    Emitter<TradeState> emit,
  ) async {
    emit(state.copyWith(isSubmittingSwap: true, clearSwapResult: true));
    try {
      final bool ok = await _tradeRepository.swap(
        fromSymbol: event.fromSymbol,
        toSymbol: event.toSymbol,
        amount: event.amount,
      );
      emit(state.copyWith(isSubmittingSwap: false, lastSwapSucceeded: ok));
    } catch (error) {
      emit(
        state.copyWith(
          isSubmittingSwap: false,
          lastSwapSucceeded: false,
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
  void _onPricesUpdated(
    _PricesUpdated event,
    Emitter<TradeState> emit,
  ) {
    final TradePairSnapshot? snapshot = state.snapshot;
    if (snapshot == null) return;

    final String symbol = snapshot.base.symbol;
    final double newPrice = _priceFeed.currentPrice(symbol);
    final DateTime yesterday =
        _clock.now().subtract(const Duration(hours: 24));
    final double yesterdayPrice = _priceFeed.priceAt(symbol, yesterday);
    final double changePct = yesterdayPrice == 0
        ? 0.0
        : ((newPrice - yesterdayPrice) / yesterdayPrice) * 100;

    if (newPrice == snapshot.price && changePct == snapshot.changePercent) {
      return;
    }

    emit(
      state.copyWith(
        snapshot: TradePairSnapshot(
          base: snapshot.base,
          quote: snapshot.quote,
          price: newPrice,
          changePercent: changePct,
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
