import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/portfolio_holding.dart';
import '../../../data/repositories/portfolio_repository.dart';
import 'portfolio_event.dart';
import 'portfolio_state.dart';

class PortfolioBloc extends Bloc<PortfolioEvent, PortfolioState> {
  PortfolioBloc({required PortfolioRepository portfolioRepository})
    : _portfolioRepository = portfolioRepository,
      super(const PortfolioState()) {
    on<PortfolioRequested>(_onRequested);
    on<PortfolioRefreshed>(_onRefreshed);
  }

  final PortfolioRepository _portfolioRepository;

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
}
