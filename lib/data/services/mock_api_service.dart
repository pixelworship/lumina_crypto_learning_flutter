import 'dart:math';
import 'dart:ui' show Color;

import '../../core/clock/clock.dart';
import '../models/asset_category.dart';
import '../models/balance_summary.dart';
import '../models/crypto_asset.dart';
import '../models/market_quotes_page.dart';
import '../models/order_book_entry.dart';
import '../models/portfolio_holding.dart';
import '../models/price_point.dart';
import '../models/trade_pair_snapshot.dart';
import 'api_service.dart';
import 'asset_catalog.dart';
import 'live_price_feed.dart';

/// In-memory implementation of [ApiService] used by the mock app.
///
/// Simulates network calls (with configurable latency) so the rest of
/// the app can be developed and tested against the same async surface
/// a real backend would expose. Swap this class out for an HTTP-backed
/// `ApiService` when the backend is ready — repositories and BLoCs
/// will not need to change.
///
/// Prices for every endpoint (markets, watchlist, portfolio, trade
/// pair) are read from the shared [LivePriceFeed], so a tick on the
/// candlestick chart and the BTC row in the markets list always
/// reflect the same value.
class MockApiService implements ApiService {
  MockApiService({
    Duration latency = const Duration(milliseconds: 450),
    Clock clock = const SystemClock(),
    AssetCatalog? catalog,
    LivePriceFeed? priceFeed,
    Random? random,
    int? seed,
  }) : _latency = latency,
       _clock = clock,
       _catalog = catalog ?? StaticAssetCatalog(),
       _random = random ?? Random(seed ?? 7) {
    // When a feed isn't provided we own one. Propagate the same clock
    // and a deterministic Random (when a seed was supplied) so two
    // services constructed with the same seed + clock produce
    // identical histories.
    _priceFeed = priceFeed ??
        LivePriceFeed(
          catalog: _catalog,
          clock: clock,
          random: seed != null ? Random(seed) : null,
        );
    _ownsFeed = priceFeed == null;
  }

  final Duration _latency;
  final Clock _clock;
  final AssetCatalog _catalog;
  final Random _random;

  late final LivePriceFeed _priceFeed;
  late final bool _ownsFeed;

  /// The shared live price feed. Exposed so the same instance can be
  /// handed to the chart's `TickRepository` / `HistoricalTickRepository`
  /// (when not provided by the caller) — i.e. so the unified data flow
  /// works even if a caller didn't pre-create the feed.
  LivePriceFeed get priceFeed => _priceFeed;

  /// Static rank assignment + watchlist set. Prices come from the feed
  /// at request time, so these are display-only metadata.
  static const List<_MarketAsset> _marketAssets = <_MarketAsset>[
    _MarketAsset(symbol: 'BTC', rank: 1),
    _MarketAsset(symbol: 'ETH', rank: 2),
    _MarketAsset(symbol: 'SOL', rank: 3),
    _MarketAsset(symbol: 'UNI', rank: 4),
    _MarketAsset(symbol: 'ADA', rank: 5),
    _MarketAsset(symbol: 'AVAX', rank: 6),
    _MarketAsset(symbol: 'AXS', rank: 7),
    _MarketAsset(symbol: 'SAND', rank: 8),
    _MarketAsset(symbol: 'USDT', rank: 9),
  ];

  static const Set<String> _watchlistSymbols = <String>{
    'BTC',
    'ETH',
    'SOL',
    'AVAX',
  };

  // ---------------------------------------------------------------------------
  // Read endpoints.
  // ---------------------------------------------------------------------------

  @override
  Future<List<CryptoQuote>> fetchMarketQuotes() async {
    await _wait();
    return <CryptoQuote>[
      for (final _MarketAsset m in _marketAssets) _quoteFor(m.symbol, m.rank),
    ];
  }

  @override
  Future<MarketQuotesPage> fetchMarketQuotesPage({
    required int offset,
    required int limit,
  }) async {
    await _wait();
    final List<CryptoQuote> quotes = <CryptoQuote>[];
    for (int i = 0; i < limit; i++) {
      final int rank = offset + i + 1; // 1-based ranks
      final CryptoAsset asset = _assetForRank(rank);
      quotes.add(_quoteFor(asset.symbol, rank));
    }
    return MarketQuotesPage(
      quotes: quotes,
      nextOffset: offset + limit,
      // Mock catalog is effectively infinite — the generator can mint
      // a new asset for any rank, so `hasMore` never goes false.
      hasMore: true,
    );
  }

  @override
  Future<List<CryptoQuote>> fetchWatchlist() async {
    final List<CryptoQuote> all = await fetchMarketQuotes();
    return all
        .where(
          (CryptoQuote q) => _watchlistSymbols.contains(q.asset.symbol),
        )
        .toList();
  }

  @override
  Future<BalanceSummary> fetchBalanceSummary() async {
    await _wait();
    final PortfolioSummary portfolio = await fetchPortfolio();
    return BalanceSummary(
      totalBalanceUsd: portfolio.totalValueUsd,
      change24hUsd: portfolio.changeTodayUsd,
      change24hPercent: portfolio.changeTodayPercent,
      sparkline: _generateSparkline(
        startPrice: portfolio.totalValueUsd * 0.96,
        endPrice: portfolio.totalValueUsd,
        points: 48,
        volatility: portfolio.totalValueUsd * 0.005,
        intervalBetweenPoints: const Duration(minutes: 30),
      ),
    );
  }

  @override
  Future<PortfolioSummary> fetchPortfolio() async {
    await _wait();
    final List<_HoldingSpec> specs = const <_HoldingSpec>[
      _HoldingSpec(symbol: 'BTC', quantity: 1.2168, costBasisPerUnit: 51343.42),
      _HoldingSpec(symbol: 'ETH', quantity: 10.85, costBasisPerUnit: 2895.10),
      _HoldingSpec(symbol: 'SOL', quantity: 128.42, costBasisPerUnit: 84.20),
      _HoldingSpec(symbol: 'ADA', quantity: 25876.55, costBasisPerUnit: 0.388),
    ];

    final List<PortfolioHolding> holdings = <PortfolioHolding>[
      for (final _HoldingSpec spec in specs)
        PortfolioHolding(
          asset: _require(spec.symbol),
          quantity: spec.quantity,
          currentPrice: _priceFeed.currentPrice(spec.symbol),
          costBasisPerUnit: spec.costBasisPerUnit,
          allocationPercent: 0,
        ),
    ];

    final double total = holdings.fold<double>(
      0.0,
      (double sum, PortfolioHolding h) => sum + h.marketValue,
    );

    // Derive a 24h change from the same noise curve so the change
    // pill reflects what's actually happened on the chart.
    final DateTime yesterday = _clock.now().subtract(const Duration(hours: 24));
    final double yesterdayTotal = specs.fold<double>(
      0.0,
      (double sum, _HoldingSpec spec) =>
          sum + (_priceFeed.priceAt(spec.symbol, yesterday) * spec.quantity),
    );
    final double change24h = total - yesterdayTotal;
    final double change24hPercent =
        yesterdayTotal == 0 ? 0 : (change24h / yesterdayTotal) * 100;

    return PortfolioSummary(
      totalValueUsd: total,
      changeTodayUsd: change24h,
      changeTodayPercent: change24hPercent,
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
    final double currentPrice = _priceFeed.currentPrice(baseSymbol);

    final DateTime yesterday = _clock.now().subtract(const Duration(hours: 24));
    final double yesterdayPrice =
        _priceFeed.priceAt(baseSymbol, yesterday);
    final double changePercent = yesterdayPrice == 0
        ? 0
        : ((currentPrice - yesterdayPrice) / yesterdayPrice) * 100;

    final List<PricePoint> history = _generateSparkline(
      startPrice: _startPriceForRange(range, currentPrice),
      endPrice: currentPrice,
      points: _pointsForRange(range),
      volatility: _volatilityForRange(range, currentPrice),
      intervalBetweenPoints: _intervalForRange(range),
    );

    // Build a small order book around the live price so bids/asks
    // track current market — even though we don't render the panel
    // anymore, downstream consumers of the API still expect it.
    final List<OrderBookEntry> bids = _ladder(
      price: currentPrice,
      direction: -1,
      side: OrderSide.bid,
    );
    final List<OrderBookEntry> asks = _ladder(
      price: currentPrice,
      direction: 1,
      side: OrderSide.ask,
    );

    return TradePairSnapshot(
      base: base,
      quote: quote,
      price: currentPrice,
      changePercent: changePercent,
      range: range,
      priceHistory: history,
      bids: bids,
      asks: asks,
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

  /// Releases the owned [LivePriceFeed] when this service constructed
  /// one itself (i.e. no feed was passed in). When a caller injected
  /// a feed, ownership stays with the caller.
  Future<void> dispose() async {
    if (_ownsFeed) await _priceFeed.dispose();
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

  /// Returns the asset that should occupy [rank] (1-based) in the
  /// markets list. Ranks within the static seed map to the canonical
  /// catalog entries; everything beyond is synthesized on demand and
  /// registered with the shared [AssetCatalog] so the rest of the app
  /// (asset detail tap, chart bloc, etc.) can resolve them by symbol
  /// without further coordination.
  CryptoAsset _assetForRank(int rank) {
    if (rank <= _marketAssets.length) {
      return _require(_marketAssets[rank - 1].symbol);
    }
    return _generatedByRank.putIfAbsent(rank, () => _generateAsset(rank));
  }

  CryptoAsset _generateAsset(int rank) {
    final int idx = rank - _marketAssets.length - 1;
    final String root = _mockRoots[idx % _mockRoots.length];
    // Cycle index — once we wrap past the root pool, append a v2/v3
    // suffix so symbols stay unique while keeping the brand short.
    final int cycle = idx ~/ _mockRoots.length;
    final String symbol = cycle == 0 ? root : '$root${cycle + 1}';
    final String name = cycle == 0
        ? _capitalize(root.toLowerCase())
        : '${_capitalize(root.toLowerCase())} v${cycle + 1}';
    final Color color = _mockColors[idx % _mockColors.length];
    final AssetCategory category =
        _mockCategoryRotation[idx % _mockCategoryRotation.length];
    final CryptoAsset asset = CryptoAsset(
      id: symbol.toLowerCase(),
      symbol: symbol,
      name: name,
      color: color,
      iconLetter: symbol[0],
      categories: <AssetCategory>[category],
    );
    return _catalog.register(asset);
  }

  /// Cache so two fetches of the same page produce the same assets
  /// (a real backend would do the equivalent at the catalog layer).
  final Map<int, CryptoAsset> _generatedByRank = <int, CryptoAsset>{};

  /// Builds a [CryptoQuote] for [symbol] using the feed for both the
  /// current and 24-hour-ago price.
  CryptoQuote _quoteFor(String symbol, int rank) {
    final double currentPrice = _priceFeed.currentPrice(symbol);
    final DateTime yesterday = _clock.now().subtract(const Duration(hours: 24));
    final double yesterdayPrice = _priceFeed.priceAt(symbol, yesterday);
    final double change24hAbsolute = currentPrice - yesterdayPrice;
    final double change24hPercent = yesterdayPrice == 0
        ? 0
        : (change24hAbsolute / yesterdayPrice) * 100;
    return CryptoQuote(
      asset: _require(symbol),
      rank: rank,
      price: currentPrice,
      change24hPercent: change24hPercent,
      change24hAbsolute: change24hAbsolute,
    );
  }

  /// Builds a 5-level order book ladder around [price]. [direction]
  /// is -1 for bids (descending) and +1 for asks (ascending).
  List<OrderBookEntry> _ladder({
    required double price,
    required int direction,
    required OrderSide side,
  }) {
    // Step is ~0.001% of the price so $64,000 BTC has ~64-cent steps
    // and $0.40 ADA has ~0.0004 steps — both feel "tight".
    final double step = price.abs() * 0.0001;
    return <OrderBookEntry>[
      for (int i = 1; i <= 5; i++)
        OrderBookEntry(
          price: price + direction * step * i,
          amount: 0.1 + _random.nextDouble() * 2.4,
          side: side,
        ),
    ];
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

  double _volatilityForRange(ChartRange range, double price) {
    // Scale volatility to the price magnitude so smaller-priced assets
    // don't oscillate beyond their reasonable range.
    final double scale = price.abs();
    switch (range) {
      case ChartRange.oneHour:
        return scale * 0.0015;
      case ChartRange.oneDay:
        return scale * 0.005;
      case ChartRange.oneWeek:
        return scale * 0.012;
      case ChartRange.oneMonth:
        return scale * 0.025;
      case ChartRange.oneYear:
        return scale * 0.08;
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

  /// Generates a smooth, vaguely realistic-looking line that ends at
  /// exactly [endPrice], with the **last point landing on
  /// `clock.now()`** and prior points striding backwards in
  /// [intervalBetweenPoints] increments. This keeps the chart
  /// anchored to "right now" and makes test assertions trivial when
  /// the clock is fake.
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

class _MarketAsset {
  const _MarketAsset({required this.symbol, required this.rank});

  final String symbol;
  final int rank;
}

/// Word pool for synthesized markets-page assets. Picked to sound
/// plausibly cryptoy without overlapping with real ticker symbols.
const List<String> _mockRoots = <String>[
  'NOVA', 'FLUX', 'AXON', 'RIFT', 'VEIL', 'ECHO', 'AURA', 'HELIX',
  'PRISM', 'KAIRO', 'CYAN', 'ORCA', 'ZEPH', 'NIMBO', 'PULSE',
  'ATLAS', 'IRIS', 'OMEGA', 'GLACI', 'EMBER', 'TIDAL', 'COMET',
  'METEOR', 'LYNX', 'RAVEN', 'ZEAL', 'SAGE', 'JADE', 'AURO',
  'PHOTON', 'QUARK', 'NEUTRO', 'PLASMA', 'VEXA', 'DRIFT', 'CINDR',
  'KINETIC', 'ORBIT', 'ZENITH', 'VANTA', 'LUMEN', 'VERTEX',
];

/// Color pool — the visible icon background for each generated row.
/// Cycled by index so adjacent rows never clash.
const List<Color> _mockColors = <Color>[
  Color(0xFF4ADE80), // green
  Color(0xFFF59E0B), // amber
  Color(0xFFEF4444), // red
  Color(0xFF8B5CF6), // violet
  Color(0xFF06B6D4), // cyan
  Color(0xFFEC4899), // pink
  Color(0xFF22C55E), // emerald
  Color(0xFFF97316), // orange
  Color(0xFF3B82F6), // blue
  Color(0xFFFBBF24), // yellow
  Color(0xFFA855F7), // purple
  Color(0xFF14B8A6), // teal
];

/// Category rotation so the four filter chips on the markets screen
/// always have results regardless of how many pages the user loads.
const List<AssetCategory> _mockCategoryRotation = <AssetCategory>[
  AssetCategory.defi,
  AssetCategory.layer1,
  AssetCategory.gaming,
  AssetCategory.defi,
  AssetCategory.layer1,
  AssetCategory.stablecoin,
  AssetCategory.gaming,
  AssetCategory.layer1,
];

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

class _HoldingSpec {
  const _HoldingSpec({
    required this.symbol,
    required this.quantity,
    required this.costBasisPerUnit,
  });

  final String symbol;
  final double quantity;
  final double costBasisPerUnit;
}
