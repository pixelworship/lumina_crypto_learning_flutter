import 'package:equatable/equatable.dart';

import '../../../data/models/trade_pair_snapshot.dart';

abstract class TradeEvent extends Equatable {
  const TradeEvent();

  @override
  List<Object?> get props => <Object?>[];
}

class TradeRequested extends TradeEvent {
  const TradeRequested({this.baseSymbol = 'BTC', this.quoteSymbol = 'USDT'});

  final String baseSymbol;
  final String quoteSymbol;

  @override
  List<Object?> get props => <Object?>[baseSymbol, quoteSymbol];
}

class TradeRangeChanged extends TradeEvent {
  const TradeRangeChanged(this.range);

  final ChartRange range;

  @override
  List<Object?> get props => <Object?>[range];
}

class TradeRefreshed extends TradeEvent {
  const TradeRefreshed();
}

/// User pressed the "Purchase {symbol}" button.
///
/// Buy-only by design — quote currency is always paid out, base
/// currency is always received. The schema keeps `fromSymbol` /
/// `toSymbol` (rather than `baseSymbol` only) so a future Sell
/// button can dispatch the same event with the symbols flipped
/// without touching the bloc / repository signatures.
class TradePurchaseSubmitted extends TradeEvent {
  const TradePurchaseSubmitted({
    required this.fromSymbol,
    required this.toSymbol,
    required this.amount,
  });

  /// Currency the user is paying with (e.g. `USDT`).
  final String fromSymbol;

  /// Currency the user is buying (e.g. `BTC`).
  final String toSymbol;

  /// Quantity of [toSymbol] to buy.
  final double amount;

  @override
  List<Object?> get props => <Object?>[fromSymbol, toSymbol, amount];
}
