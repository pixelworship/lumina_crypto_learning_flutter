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
/// Quote currency is paid out, base currency is received. The schema
/// keeps `fromSymbol` / `toSymbol` (rather than `baseSymbol` only)
/// so [TradeSaleSubmitted] can reuse the same direction-aware
/// repository call with the symbols flipped.
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

/// User pressed the "Sell {symbol}" button.
///
/// Mirror of [TradePurchaseSubmitted] with the trade direction
/// reversed — base currency is paid out, quote currency is received.
/// Lives as a separate event (instead of a `side` field on the
/// purchase event) so the bloc can route to a dedicated handler and
/// record `FillSide.sell` for the chart's marker overlay; the
/// underlying repository call is the same direction-agnostic
/// `purchase(...)` so we don't have to extend the mock API surface.
class TradeSaleSubmitted extends TradeEvent {
  const TradeSaleSubmitted({
    required this.fromSymbol,
    required this.toSymbol,
    required this.amount,
  });

  /// Currency the user is giving up (e.g. `BTC`).
  final String fromSymbol;

  /// Currency the user is receiving (e.g. `USDT`).
  final String toSymbol;

  /// Quantity of [fromSymbol] to sell.
  final double amount;

  @override
  List<Object?> get props => <Object?>[fromSymbol, toSymbol, amount];
}
