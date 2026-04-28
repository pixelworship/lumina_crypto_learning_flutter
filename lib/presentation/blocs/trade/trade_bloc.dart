import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/trade_pair_snapshot.dart';
import '../../../data/repositories/trade_repository.dart';
import 'trade_event.dart';
import 'trade_state.dart';

class TradeBloc extends Bloc<TradeEvent, TradeState> {
  TradeBloc({required TradeRepository tradeRepository})
    : _tradeRepository = tradeRepository,
      super(const TradeState()) {
    on<TradeRequested>(_onRequested);
    on<TradeRangeChanged>(_onRangeChanged);
    on<TradeRefreshed>(_onRefreshed);
    on<TradeSwapSubmitted>(_onSwap);
  }

  final TradeRepository _tradeRepository;

  Future<void> _onRequested(
    TradeRequested event,
    Emitter<TradeState> emit,
  ) async {
    emit(
      state.copyWith(
        status: TradeStatus.loading,
        baseSymbol: event.baseSymbol,
        quoteSymbol: event.quoteSymbol,
        clearError: true,
      ),
    );
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
      final TradePairSnapshot snapshot = await _tradeRepository.getPair(
        baseSymbol: state.baseSymbol,
        quoteSymbol: state.quoteSymbol,
        range: state.range,
      );
      emit(
        state.copyWith(
          status: TradeStatus.success,
          snapshot: snapshot,
          clearError: true,
        ),
      );
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
}
