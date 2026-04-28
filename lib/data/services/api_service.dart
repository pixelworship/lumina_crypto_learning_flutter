import '../models/balance_summary.dart';
import '../models/crypto_asset.dart';
import '../models/portfolio_holding.dart';
import '../models/trade_pair_snapshot.dart';

/// Abstract API surface.
///
/// Mirrors the endpoints a real backend would expose. Repositories depend on
/// this interface so that:
///   * production code can wire up an HTTP-backed implementation,
///   * the mock app can wire up [MockApiService],
///   * tests can substitute a `mocktail`-generated stub.
///
/// **All methods are async** to model the network round-trip honestly. Even if
/// a test implementation returns synchronously, callers should treat results
/// as futures so swapping in a real network client is transparent.
abstract class ApiService {
  /// `GET /markets/quotes` — top-of-book pricing for every supported asset.
  Future<List<CryptoQuote>> fetchMarketQuotes();

  /// `GET /accounts/watchlist` — the user's followed assets.
  Future<List<CryptoQuote>> fetchWatchlist();

  /// `GET /accounts/balance` — aggregate balance + 24h change + sparkline.
  Future<BalanceSummary> fetchBalanceSummary();

  /// `GET /accounts/portfolio` — full holdings list with allocation %.
  Future<PortfolioSummary> fetchPortfolio();

  /// `GET /trade/pair?base=BTC&quote=USDT&range=1H`
  Future<TradePairSnapshot> fetchTradePair({
    required String baseSymbol,
    required String quoteSymbol,
    required ChartRange range,
  });

  /// `POST /trade/swap` — submits a swap; returns whether it was accepted.
  Future<bool> submitSwap({
    required String fromSymbol,
    required String toSymbol,
    required double amount,
  });

  /// `POST /transactions/deposit`
  Future<bool> submitDeposit({required double amountUsd});

  /// `POST /transactions/withdraw`
  Future<bool> submitWithdrawal({required double amountUsd});
}
