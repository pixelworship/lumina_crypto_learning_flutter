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
    this.isSubmittingPurchase = false,
    this.lastPurchaseSucceeded,
    this.isSubmittingSale = false,
    this.lastSaleSucceeded,
    this.errorMessage,
  });

  final TradeStatus status;
  final TradePairSnapshot? snapshot;
  final ChartRange range;
  final String baseSymbol;
  final String quoteSymbol;

  /// True while a `TradePurchaseSubmitted` is in flight. Drives the
  /// purchase button's spinner + disables re-submit.
  final bool isSubmittingPurchase;

  /// One-shot result of the most recent purchase, surfaced to the UI
  /// as a snackbar. `null` between submissions; `true` on accept;
  /// `false` on reject or thrown exception.
  final bool? lastPurchaseSucceeded;

  /// True while a `TradeSaleSubmitted` is in flight. Drives the sell
  /// button's spinner + disables re-submit. Mirror of
  /// [isSubmittingPurchase].
  final bool isSubmittingSale;

  /// One-shot result of the most recent sale. Same null / true / false
  /// semantics as [lastPurchaseSucceeded]; kept on a separate field so
  /// the buy and sell snackbar listeners can fire independently
  /// (otherwise a buy that lands while a sale's result is still
  /// pending would clobber it).
  final bool? lastSaleSucceeded;

  final String? errorMessage;

  TradeState copyWith({
    TradeStatus? status,
    TradePairSnapshot? snapshot,
    ChartRange? range,
    String? baseSymbol,
    String? quoteSymbol,
    bool? isSubmittingPurchase,
    bool? lastPurchaseSucceeded,
    bool? isSubmittingSale,
    bool? lastSaleSucceeded,
    String? errorMessage,
    bool clearError = false,
    bool clearPurchaseResult = false,
    bool clearSaleResult = false,
  }) {
    return TradeState(
      status: status ?? this.status,
      snapshot: snapshot ?? this.snapshot,
      range: range ?? this.range,
      baseSymbol: baseSymbol ?? this.baseSymbol,
      quoteSymbol: quoteSymbol ?? this.quoteSymbol,
      isSubmittingPurchase:
          isSubmittingPurchase ?? this.isSubmittingPurchase,
      lastPurchaseSucceeded: clearPurchaseResult
          ? null
          : (lastPurchaseSucceeded ?? this.lastPurchaseSucceeded),
      isSubmittingSale: isSubmittingSale ?? this.isSubmittingSale,
      lastSaleSucceeded: clearSaleResult
          ? null
          : (lastSaleSucceeded ?? this.lastSaleSucceeded),
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
    isSubmittingPurchase,
    lastPurchaseSucceeded,
    isSubmittingSale,
    lastSaleSucceeded,
    errorMessage,
  ];
}
