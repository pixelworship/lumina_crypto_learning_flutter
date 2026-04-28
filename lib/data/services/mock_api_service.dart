import 'dart:math';

import '../../core/clock/clock.dart';
import '../models/balance_summary.dart';
import '../models/crypto_asset.dart';
import '../models/order_book_entry.dart';
import '../models/portfolio_holding.dart';
import '../models/price_point.dart';
import '../models/trade_pair_snapshot.dart';
import 'api_service.dart';
import 'asset_catalog.dart';

/// In-memory implementation of [ApiService] used by the mock app.
///
/// Simulates network calls (with configurable latency) so the rest of the app
/// can be developed and tested against the same async surface a real backend
/// would expose. Swap this class out for an HTTP-backed `ApiService` when the
/// backend is ready — repositories and BLoCs will not need to change.
///
/// All non-determinism is injected:
///   * [Clock] for current-time stamps,
///   * [Random] for sparkline noise,
///   * [AssetCatalog] for asset resolution.
///
/// This keeps tests deterministic and the public API painlessly mockable.
class MockApiService implements ApiService {
  MockApiService({
    Duration latency = const Duration(milliseconds: 450),
    Clock clock = const SystemClock(),
    AssetCatalog? catalog,
    Random? random,
    int? seed,
  }) : _latency = latency,
       _clock = clock,
       _catalog = catalog ?? StaticAssetCatalog(),
       _random = random ?? Random(seed ?? 7);

  final Duration _latency;
  final Clock _clock;
  final AssetCatalog _catalog;
  final Random _random;

  // ---------------------------------------------------------------------------
  // Read endpoints.
  // ---------------------------------------------------------------------------

  @override
  Future<List<CryptoQuote>> fetchMarketQuotes() async {
    await _wait();
    return <CryptoQuote>[
      CryptoQuote(
        asset: _require('BTC'),
        rank: 1,
        price: 64230.50,
        change24hPercent: 2.4,
        change24hAbsolute: 1502.35,
      ),
      CryptoQuote(
        asset: _require('ETH'),
        rank: 2,
        price: 3450.12,
        change24hPercent: -1.2,
        change24hAbsolute: -42.18,
      ),
      CryptoQuote(
        asset: _require('SOL'),
        rank: 3,
        price: 145.80,
        change24hPercent: 8.7,
        change24hAbsolute: 11.65,
      ),
      CryptoQuote(
        asset: _require('UNI'),
        rank: 4,
        price: 11.24,
        change24hPercent: 0.5,
        change24hAbsolute: 0.06,
      ),
      CryptoQuote(
        asset: _require('ADA'),
        rank: 5,
        price: 0.482,
        change24hPercent: -2.1,
        change24hAbsolute: -0.010,
      ),
      CryptoQuote(
        asset: _require('AVAX'),
        rank: 6,
        price: 38.65,
        change24hPercent: 4.3,
        change24hAbsolute: 1.59,
      ),
      CryptoQuote(
        asset: _require('AXS'),
        rank: 7,
        price: 7.85,
        change24hPercent: -0.9,
        change24hAbsolute: -0.07,
      ),
      CryptoQuote(
        asset: _require('SAND'),
        rank: 8,
        price: 0.421,
        change24hPercent: 3.2,
        change24hAbsolute: 0.013,
      ),
      CryptoQuote(
        asset: _require('USDT'),
        rank: 9,
        price: 1.00,
        change24hPercent: 0.01,
        change24hAbsolute: 0.0001,
      ),
    ];
  }

  @override
  Future<List<CryptoQuote>> fetchWatchlist() async {
    final List<CryptoQuote> all = await fetchMarketQuotes();
    const Set<String> watched = <String>{'btc', 'eth', 'sol', 'avax'};
    return all.where((CryptoQuote q) => watched.contains(q.asset.id)).toList();
  }

  @override
  Future<BalanceSummary> fetchBalanceSummary() async {
    await _wait();
    return BalanceSummary(
      totalBalanceUsd: 142850.24,
      change24hUsd: 3420.50,
      change24hPercent: 2.4,
      sparkline: _generateSparkline(
        startPrice: 138000,
        endPrice: 142850,
        points: 48,
        volatility: 600,
        intervalBetweenPoints: const Duration(minutes: 30),
      ),
    );
  }

  @override
  Future<PortfolioSummary> fetchPortfolio() async {
    await _wait();
    final List<PortfolioHolding> holdings = <PortfolioHolding>[
      PortfolioHolding(
        asset: _require('BTC'),
        quantity: 1.2168,
        currentPrice: 64230.50,
        costBasisPerUnit: 51343.42,
        allocationPercent: 45,
      ),
      PortfolioHolding(
        asset: _require('ETH'),
        quantity: 10.85,
        currentPrice: 3450.12,
        costBasisPerUnit: 2895.10,
        allocationPercent: 30,
      ),
      PortfolioHolding(
        asset: _require('SOL'),
        quantity: 128.42,
        currentPrice: 145.80,
        costBasisPerUnit: 84.20,
        allocationPercent: 15,
      ),
      PortfolioHolding(
        asset: _require('ADA'),
        quantity: 25876.55,
        currentPrice: 0.482,
        costBasisPerUnit: 0.388,
        allocationPercent: 10,
      ),
    ];

    final double total = holdings.fold<double>(
      0.0,
      (double sum, PortfolioHolding h) => sum + h.marketValue,
    );

    return PortfolioSummary(
      totalValueUsd: 124850.42,
      changeTodayUsd: 3420.50,
      changeTodayPercent: 2.8,
      holdings: holdings.map((PortfolioHolding h) {
        return PortfolioHolding(
          asset: h.asset,
          quantity: h.quantity,
          currentPrice: h.currentPrice,
          costBasisPerUnit: h.costBasisPerUnit,
          allocationPercent: total == 0 ? 0 : (h.marketValue / total) * 100,
        );
      }).toList(),
    );
  }

  @override
  Future<TradePairSnapshot> fetchTradePair({
    required String baseSymbol,
    required String quoteSymbol,
    required ChartRange range,
  }) async {
    await _wait();

    final CryptoAsset base = _require(baseSymbol);
    final CryptoAsset quote = _require(quoteSymbol);

    const double currentPrice = 64289.50;
    final List<PricePoint> history = _generateSparkline(
      startPrice: _startPriceForRange(range, currentPrice),
      endPrice: currentPrice,
      points: _pointsForRange(range),
      volatility: _volatilityForRange(range),
      intervalBetweenPoints: _intervalForRange(range),
    );

    return TradePairSnapshot(
      base: base,
      quote: quote,
      price: currentPrice,
      changePercent: 2.46,
      range: range,
      priceHistory: history,
      bids: const <OrderBookEntry>[
        OrderBookEntry(price: 64289.45, amount: 0.4500, side: OrderSide.bid),
        OrderBookEntry(price: 64288.50, amount: 1.2000, side: OrderSide.bid),
        OrderBookEntry(price: 64287.00, amount: 0.8500, side: OrderSide.bid),
        OrderBookEntry(price: 64285.10, amount: 2.1000, side: OrderSide.bid),
        OrderBookEntry(price: 64283.20, amount: 0.6700, side: OrderSide.bid),
      ],
      asks: const <OrderBookEntry>[
        OrderBookEntry(price: 64290.00, amount: 0.1500, side: OrderSide.ask),
        OrderBookEntry(price: 64291.50, amount: 2.1000, side: OrderSide.ask),
        OrderBookEntry(price: 64292.10, amount: 0.5000, side: OrderSide.ask),
        OrderBookEntry(price: 64293.00, amount: 0.5000, side: OrderSide.ask),
        OrderBookEntry(price: 64295.40, amount: 1.8500, side: OrderSide.ask),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Write endpoints.
  // ---------------------------------------------------------------------------

  @override
  Future<bool> submitSwap({
    required String fromSymbol,
    required String toSymbol,
    required double amount,
  }) async {
    if (amount <= 0) return false;
    if (_catalog.findBySymbol(fromSymbol) == null) return false;
    if (_catalog.findBySymbol(toSymbol) == null) return false;
    await _wait();
    return true;
  }

  @override
  Future<bool> submitDeposit({required double amountUsd}) async {
    if (amountUsd <= 0) return false;
    await _wait();
    return true;
  }

  @override
  Future<bool> submitWithdrawal({required double amountUsd}) async {
    if (amountUsd <= 0) return false;
    await _wait();
    return true;
  }

  // ---------------------------------------------------------------------------
  // Helpers.
  // ---------------------------------------------------------------------------

  Future<void> _wait() => Future<void>.delayed(_latency);

  CryptoAsset _require(String symbol) {
    final CryptoAsset? a = _catalog.findBySymbol(symbol);
    if (a == null) {
      throw ArgumentError.value(symbol, 'symbol', 'Unknown asset symbol');
    }
    return a;
  }

  int _pointsForRange(ChartRange range) {
    switch (range) {
      case ChartRange.oneHour:
        return 60;
      case ChartRange.oneDay:
        return 96;
      case ChartRange.oneWeek:
        return 84;
      case ChartRange.oneMonth:
        return 60;
      case ChartRange.oneYear:
        return 52;
    }
  }

  double _volatilityForRange(ChartRange range) {
    switch (range) {
      case ChartRange.oneHour:
        return 80;
      case ChartRange.oneDay:
        return 250;
      case ChartRange.oneWeek:
        return 600;
      case ChartRange.oneMonth:
        return 1100;
      case ChartRange.oneYear:
        return 4500;
    }
  }

  double _startPriceForRange(ChartRange range, double end) {
    switch (range) {
      case ChartRange.oneHour:
        return end * 0.995;
      case ChartRange.oneDay:
        return end * 0.976;
      case ChartRange.oneWeek:
        return end * 0.92;
      case ChartRange.oneMonth:
        return end * 0.85;
      case ChartRange.oneYear:
        return end * 0.55;
    }
  }

  Duration _intervalForRange(ChartRange range) {
    switch (range) {
      case ChartRange.oneHour:
        return const Duration(minutes: 1);
      case ChartRange.oneDay:
        return const Duration(minutes: 15);
      case ChartRange.oneWeek:
        return const Duration(hours: 2);
      case ChartRange.oneMonth:
        return const Duration(hours: 12);
      case ChartRange.oneYear:
        return const Duration(days: 7);
    }
  }

  /// Generates a smooth, vaguely realistic-looking line that ends at exactly
  /// [endPrice], with the **last point landing on `clock.now()`** and prior
  /// points striding backwards in [intervalBetweenPoints] increments. This
  /// keeps the chart anchored to "right now" and makes test assertions trivial
  /// when the clock is fake.
  List<PricePoint> _generateSparkline({
    required double startPrice,
    required double endPrice,
    required int points,
    required double volatility,
    required Duration intervalBetweenPoints,
  }) {
    final List<PricePoint> result = <PricePoint>[];
    final DateTime now = _clock.now();
    double current = startPrice;
    final double trend = (endPrice - startPrice) / points;

    for (int i = 0; i < points; i++) {
      final double noise = (_random.nextDouble() - 0.5) * volatility * 0.3;
      current += trend + noise;
      result.add(
        PricePoint(
          timestamp: now.subtract(intervalBetweenPoints * (points - 1 - i)),
          price: current,
        ),
      );
    }
    if (result.isNotEmpty) {
      result[result.length - 1] = PricePoint(
        timestamp: result.last.timestamp,
        price: endPrice,
      );
    }
    return result;
  }
}
