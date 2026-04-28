import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/crypto_asset.dart';
import '../../../data/repositories/market_repository.dart';
import 'markets_event.dart';
import 'markets_state.dart';

class MarketsBloc extends Bloc<MarketsEvent, MarketsState> {
  MarketsBloc({required MarketRepository marketRepository})
    : _marketRepository = marketRepository,
      super(const MarketsState()) {
    on<MarketsRequested>(_onRequested);
    on<MarketsRefreshed>(_onRefreshed);
    on<MarketsCategoryChanged>(_onCategoryChanged);
    on<MarketsSearchChanged>(_onSearchChanged);
  }

  final MarketRepository _marketRepository;

  Future<void> _onRequested(
    MarketsRequested event,
    Emitter<MarketsState> emit,
  ) async {
    emit(state.copyWith(status: MarketsStatus.loading, clearError: true));
    try {
      final List<CryptoQuote> quotes = await _marketRepository
          .getMarketQuotes();
      emit(state.copyWith(status: MarketsStatus.success, quotes: quotes));
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
      final List<CryptoQuote> quotes = await _marketRepository
          .getMarketQuotes();
      emit(
        state.copyWith(
          status: MarketsStatus.success,
          quotes: quotes,
          clearError: true,
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
}
