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

class TradeSwapSubmitted extends TradeEvent {
  const TradeSwapSubmitted({
    required this.fromSymbol,
    required this.toSymbol,
    required this.amount,
  });

  final String fromSymbol;
  final String toSymbol;
  final double amount;

  @override
  List<Object?> get props => <Object?>[fromSymbol, toSymbol, amount];
}
