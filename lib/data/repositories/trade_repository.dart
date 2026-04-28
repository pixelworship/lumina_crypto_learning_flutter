import '../models/trade_pair_snapshot.dart';
import '../services/api_service.dart';

/// Repository abstraction over a single tradable pair + swap submission.
abstract class TradeRepository {
  Future<TradePairSnapshot> getPair({
    required String baseSymbol,
    required String quoteSymbol,
    required ChartRange range,
  });

  Future<bool> swap({
    required String fromSymbol,
    required String toSymbol,
    required double amount,
  });
}

class MockTradeRepository implements TradeRepository {
  MockTradeRepository(this._api);

  final ApiService _api;

  @override
  Future<TradePairSnapshot> getPair({
    required String baseSymbol,
    required String quoteSymbol,
    required ChartRange range,
  }) {
    return _api.fetchTradePair(
      baseSymbol: baseSymbol,
      quoteSymbol: quoteSymbol,
      range: range,
    );
  }

  @override
  Future<bool> swap({
    required String fromSymbol,
    required String toSymbol,
    required double amount,
  }) {
    return _api.submitSwap(
      fromSymbol: fromSymbol,
      toSymbol: toSymbol,
      amount: amount,
    );
  }
}
