import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/balance_summary.dart';
import '../../../data/models/crypto_asset.dart';
import '../../../data/repositories/market_repository.dart';
import '../../../data/repositories/portfolio_repository.dart';
import 'home_event.dart';
import 'home_state.dart';

class HomeBloc extends Bloc<HomeEvent, HomeState> {
  HomeBloc({
    required PortfolioRepository portfolioRepository,
    required MarketRepository marketRepository,
  }) : _portfolioRepository = portfolioRepository,
       _marketRepository = marketRepository,
       super(const HomeState()) {
    on<HomeRequested>(_onRequested);
    on<HomeRefreshed>(_onRefreshed);
    on<HomeQuickActionTriggered>(_onQuickAction);
  }

  final PortfolioRepository _portfolioRepository;
  final MarketRepository _marketRepository;

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
        _marketRepository.getWatchlist(),
      ]);
      emit(
        state.copyWith(
          status: HomeStatus.success,
          balance: results[0] as BalanceSummary,
          watchlist: results[1] as List<CryptoQuote>,
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
    // Quick actions are mocked - normally these would push routes.
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
}
