import '../models/trade_pair_snapshot.dart';
import '../services/api_service.dart';

/// Repository abstraction over a single tradable pair + purchase
/// submission.
///
/// `purchase` is the user-facing buy action — quote is paid out,
/// base is received. The schema preserves explicit `fromSymbol` /
/// `toSymbol` (instead of just `baseSymbol`) so a future Sell button
/// can reuse the same surface area with the symbols flipped.
abstract class TradeRepository {
  Future<TradePairSnapshot> getPair({
    required String baseSymbol,
    required String quoteSymbol,
    required ChartRange range,
  });

  Future<bool> purchase({
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
  Future<bool> purchase({
    required String fromSymbol,
    required String toSymbol,
    required double amount,
  }) {
    return _api.submitPurchase(
      fromSymbol: fromSymbol,
      toSymbol: toSymbol,
      amount: amount,
    );
  }
}
