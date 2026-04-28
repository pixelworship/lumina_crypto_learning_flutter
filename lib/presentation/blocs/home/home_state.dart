import 'package:equatable/equatable.dart';

import '../../../data/models/balance_summary.dart';
import '../../../data/models/crypto_asset.dart';

enum HomeStatus { initial, loading, success, failure }

class HomeState extends Equatable {
  const HomeState({
    this.status = HomeStatus.initial,
    this.balance,
    this.watchlist = const <CryptoQuote>[],
    this.errorMessage,
  });

  final HomeStatus status;
  final BalanceSummary? balance;
  final List<CryptoQuote> watchlist;
  final String? errorMessage;

  HomeState copyWith({
    HomeStatus? status,
    BalanceSummary? balance,
    List<CryptoQuote>? watchlist,
    String? errorMessage,
    bool clearError = false,
  }) {
    return HomeState(
      status: status ?? this.status,
      balance: balance ?? this.balance,
      watchlist: watchlist ?? this.watchlist,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    status,
    balance,
    watchlist,
    errorMessage,
  ];
}
