import 'package:equatable/equatable.dart';

import '../../../data/models/trade_pair_snapshot.dart';

enum TradeStatus { initial, loading, success, failure }

class TradeState extends Equatable {
  const TradeState({
    this.status = TradeStatus.initial,
    this.snapshot,
    this.range = ChartRange.oneDay,
    this.baseSymbol = 'BTC',
    this.quoteSymbol = 'USDT',
    this.isSubmittingSwap = false,
    this.lastSwapSucceeded,
    this.errorMessage,
  });

  final TradeStatus status;
  final TradePairSnapshot? snapshot;
  final ChartRange range;
  final String baseSymbol;
  final String quoteSymbol;
  final bool isSubmittingSwap;
  final bool? lastSwapSucceeded;
  final String? errorMessage;

  TradeState copyWith({
    TradeStatus? status,
    TradePairSnapshot? snapshot,
    ChartRange? range,
    String? baseSymbol,
    String? quoteSymbol,
    bool? isSubmittingSwap,
    bool? lastSwapSucceeded,
    String? errorMessage,
    bool clearError = false,
    bool clearSwapResult = false,
  }) {
    return TradeState(
      status: status ?? this.status,
      snapshot: snapshot ?? this.snapshot,
      range: range ?? this.range,
      baseSymbol: baseSymbol ?? this.baseSymbol,
      quoteSymbol: quoteSymbol ?? this.quoteSymbol,
      isSubmittingSwap: isSubmittingSwap ?? this.isSubmittingSwap,
      lastSwapSucceeded: clearSwapResult
          ? null
          : (lastSwapSucceeded ?? this.lastSwapSucceeded),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    status,
    snapshot,
    range,
    baseSymbol,
    quoteSymbol,
    isSubmittingSwap,
    lastSwapSucceeded,
    errorMessage,
  ];
}
