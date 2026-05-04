import '../models/crypto_asset.dart';
import '../models/market_quotes_page.dart';
import '../services/api_service.dart';

/// Repository abstraction over market data.
///
/// BLoCs depend on this interface, not the concrete implementation, so we can
/// swap the mock API for a real one without touching the presentation layer.
abstract class MarketRepository {
  Future<List<CryptoQuote>> getMarketQuotes();
  Future<List<CryptoQuote>> getWatchlist();

  /// Paginated alternative to [getMarketQuotes]. The markets discovery
  /// screen uses this to lazy-load assets in fixed-size pages so the
  /// initial render stays cheap and the scroll experience is bounded
  /// by what the user actually views.
  Future<MarketQuotesPage> getMarketQuotesPage({
    required int offset,
    required int limit,
  });
}

/// Default [MarketRepository] that delegates to an injected [ApiService].
///
/// Despite the name "Mock", this repository is the production-shape
/// implementation — it just happens to be paired with [MockApiService] today.
/// Swapping in an HTTP-backed [ApiService] requires zero changes here.
class MockMarketRepository implements MarketRepository {
  MockMarketRepository(this._api);

  final ApiService _api;

  @override
  Future<List<CryptoQuote>> getMarketQuotes() => _api.fetchMarketQuotes();

  @override
  Future<MarketQuotesPage> getMarketQuotesPage({
    required int offset,
    required int limit,
  }) =>
      _api.fetchMarketQuotesPage(offset: offset, limit: limit);

  @override
  Future<List<CryptoQuote>> getWatchlist() => _api.fetchWatchlist();
}
