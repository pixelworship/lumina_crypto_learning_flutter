import 'dart:async';
import 'dart:math';

import '../../core/clock/clock.dart';
import '../models/crypto_asset.dart';
import 'asset_catalog.dart';
import 'price_noise.dart';

/// One emission of the live price feed: the full price map for every
/// registered symbol at a single point in time.
class LivePriceUpdate {
  const LivePriceUpdate({required this.prices, required this.timestamp});

  final Map<String, double> prices;
  final DateTime timestamp;
}

/// Single source of truth for the app's live mock prices.
///
/// Each registered asset gets its own deterministic [PriceNoise] (seeded
/// off the asset's symbol so the curve is stable across hot-restarts).
/// The feed runs an irregular timer that periodically samples each
/// noise generator and broadcasts the updated price map. Consumers —
/// the candlestick chart, the markets list, the portfolio, the home
/// watchlist — all read from the same feed so a single price update
/// for an asset is reflected everywhere in the app simultaneously.
///
/// The feed also exposes the underlying [PriceNoise] for each symbol
/// so historical mock data shares the exact same curve as live ticks.
class LivePriceFeed {
  LivePriceFeed({
    required AssetCatalog catalog,
    int seed = 0xCAFE,
    int minDelayMs = 200,
    int maxDelayMs = 1000,
    Random? random,
    Clock clock = const SystemClock(),
    bool startPaused = false,
  }) : _random = random ?? Random(),
       _clock = clock,
       _minDelayMs = minDelayMs,
       _maxDelayMs = maxDelayMs,
       _paused = startPaused,
       _seed = seed {
    for (final CryptoAsset asset in catalog.all()) {
      _ensureNoise(asset.symbol);
    }
    // Seed initial prices so synchronous reads work before the first
    // timer tick fires (even when starting paused).
    _seedInitialPrices();
    _scheduleNextTick();
  }

  /// Returns the cached noise generator for [symbol], lazily creating
  /// one (with a deterministic seed derived from the symbol) when the
  /// feed hasn't seen this asset before. Used so paginated/mock-only
  /// assets minted after construction get prices automatically without
  /// the caller having to register them up front.
  PriceNoise _ensureNoise(String symbol) {
    final String key = symbol.toUpperCase();
    final PriceNoise? existing = _noises[key];
    if (existing != null) return existing;
    final int symbolSeed = _seed ^ key.hashCode;
    final double basePrice = _basePriceFor(key);
    final PriceNoise noise = PriceNoise(
      seed: symbolSeed,
      basePrice: basePrice,
      // Volatility scaled to the base price so a $0.50 token doesn't
      // swing as wildly as a $50,000 BTC.
      macroAmplitude: basePrice * 0.4,
      microAmplitude: basePrice * 0.02,
    );
    _noises[key] = noise;
    final double price = (noise.priceAt(_clock.now()) + (_offsets[key] ?? 0))
        .clamp(0.0001, double.infinity);
    _currentPrices[key] =
        double.parse(price.toStringAsFixed(_decimalsFor(price)));
    return noise;
  }

  void _seedInitialPrices() {
    final DateTime now = _clock.now();
    for (final MapEntry<String, PriceNoise> entry in _noises.entries) {
      final String symbol = entry.key;
      final PriceNoise noise = entry.value;
      final double base = noise.priceAt(now) + (_offsets[symbol] ?? 0);
      final double price = base.clamp(0.0001, double.infinity);
      _currentPrices[symbol] =
          double.parse(price.toStringAsFixed(_decimalsFor(price)));
    }
  }

  /// Approximate "starting" prices for each known symbol. The actual
  /// current price drifts around this base via the symbol's [PriceNoise].
  static const Map<String, double> _baseSeeds = <String, double>{
    'BTC': 64000.0,
    'ETH': 3500.0,
    'SOL': 150.0,
    'UNI': 12.0,
    'ADA': 0.45,
    'USDT': 1.00,
    'AVAX': 30.0,
    'AXS': 5.5,
    'SAND': 0.40,
  };

  /// Picks a plausible base price for any symbol. Known symbols (the
  /// real-asset seeds above) get their canonical price; unknown ones
  /// (paginated mock assets minted at runtime) get a deterministic
  /// hash-bucketed price spanning sub-dollar through five-figure
  /// ranges so the markets list looks varied as the user scrolls.
  static double _basePriceFor(String symbol) {
    final String key = symbol.toUpperCase();
    final double? known = _baseSeeds[key];
    if (known != null) return known;
    int h = 17;
    for (int i = 0; i < key.length; i++) {
      h = (h * 31 + key.codeUnitAt(i)) & 0x7fffffff;
    }
    final int bucket = h % 10;
    if (bucket < 3) {
      // Sub-dollar: $0.01 – $0.99
      return ((h % 99) + 1) / 100.0;
    } else if (bucket < 7) {
      // Mid: $1 – $99.99
      return 1.0 + ((h % 9900) / 100.0);
    } else if (bucket < 9) {
      // Large: $100 – $4,999
      return 100.0 + (h % 4900).toDouble();
    } else {
      // Headline: $5,000 – $79,999
      return 5000.0 + (h % 75000).toDouble();
    }
  }

  final Map<String, PriceNoise> _noises = <String, PriceNoise>{};
  final Map<String, double> _currentPrices = <String, double>{};
  final Map<String, double> _offsets = <String, double>{};
  final Random _random;
  final Clock _clock;
  final int _minDelayMs;
  final int _maxDelayMs;
  final int _seed;

  Timer? _timer;
  double _speedMultiplier = 1.0;
  bool _paused;
  bool _disposed = false;

  final StreamController<LivePriceUpdate> _controller =
      StreamController<LivePriceUpdate>.broadcast();

  void _scheduleNextTick() {
    if (_disposed || _paused) return;
    final int baseDelayMs =
        _minDelayMs + _random.nextInt(_maxDelayMs - _minDelayMs + 1);
    final int scaledMs =
        (baseDelayMs / _speedMultiplier).round().clamp(1, 60000);
    _timer = Timer(Duration(milliseconds: scaledMs), () {
      if (_paused || _disposed) return;
      _emit();
      _scheduleNextTick();
    });
  }

  void _emit() {
    if (_disposed || _paused) return;
    final DateTime now = _clock.now();
    for (final MapEntry<String, PriceNoise> entry in _noises.entries) {
      final String symbol = entry.key;
      final PriceNoise noise = entry.value;
      final double base = noise.priceAt(now) + (_offsets[symbol] ?? 0);
      // Small per-tick jitter for tick-to-tick spread within a candle.
      final double jitter =
          (_random.nextDouble() - 0.5) * (base.abs() * 0.001);
      final double price = (base + jitter).clamp(0.0001, double.infinity);
      _currentPrices[symbol] =
          double.parse(price.toStringAsFixed(_decimalsFor(price)));
    }
    if (_controller.isClosed) return;
    _controller.add(
      LivePriceUpdate(
        prices: Map<String, double>.unmodifiable(_currentPrices),
        timestamp: now,
      ),
    );
  }

  /// Sub-cent precision for low-priced tokens so we don't quantize a
  /// $0.40 token to a flat $0.40 forever.
  int _decimalsFor(double price) {
    if (price >= 100) return 2;
    if (price >= 1) return 4;
    return 6;
  }

  /// Broadcast stream of price updates. Each event carries the entire
  /// price map for every registered symbol. Throttle / debounce on the
  /// consumer side if the rebuild rate is too aggressive for a screen.
  Stream<LivePriceUpdate> watchAll() => _controller.stream;

  /// Returns the most recently emitted price for [symbol], or computes
  /// a fresh value from the noise curve if the feed hasn't yet emitted
  /// (e.g. during a synchronous call right after construction). Lazily
  /// registers a noise generator for unknown symbols so paginated /
  /// dynamically-minted assets work without explicit registration.
  double currentPrice(String symbol) {
    final String key = symbol.toUpperCase();
    if (_currentPrices.containsKey(key)) return _currentPrices[key]!;
    final PriceNoise noise = _ensureNoise(key);
    final double price =
        noise.priceAt(_clock.now()) + (_offsets[key] ?? 0);
    return double.parse(price.toStringAsFixed(_decimalsFor(price)));
  }

  /// Computes the price for [symbol] at an arbitrary [timestamp] using
  /// the symbol's noise curve. Used to derive 24h-ago prices for the
  /// `change24h` fields on `CryptoQuote` etc., so the change reflects
  /// the same curve the live price tracks.
  double priceAt(String symbol, DateTime timestamp) {
    final PriceNoise noise = _ensureNoise(symbol);
    final double price = noise.priceAt(timestamp);
    return double.parse(price.toStringAsFixed(_decimalsFor(price)));
  }

  /// Direct access to the [PriceNoise] for a symbol — used by the
  /// chart's history repositories so historical ticks share the same
  /// curve as live ticks. Lazily creates the generator for symbols
  /// the feed hasn't seen before (so a chart opened on a paginated
  /// asset works without pre-registration).
  PriceNoise? noiseFor(String symbol) => _ensureNoise(symbol);

  /// Current debug-driven price offset for [symbol] (default 0).
  /// Exposed so the historical API can synthesize past ticks with
  /// the same offset baked in — otherwise a debug-driven price
  /// spike would only affect live ticks, leaving every historical
  /// candle on the chart at the unaffected price.
  double priceOffset(String symbol) =>
      _offsets[symbol.toUpperCase()] ?? 0;

  /// Multiplies the base emission frequency. Values greater than 1
  /// emit ticks faster, less than 1 slower. Must be > 0.
  void setSpeedMultiplier(double multiplier) {
    if (multiplier <= 0 || !multiplier.isFinite) return;
    _speedMultiplier = multiplier;
  }

  /// Adds a constant price offset on top of the underlying noise curve
  /// for a single symbol. Useful for debug-driven price spikes /
  /// crashes.
  ///
  /// Triggers an immediate broadcast so every subscriber (the chart,
  /// the markets list, the portfolio, the home watchlist, the asset
  /// detail header) snaps to the new price on the next frame —
  /// without waiting for the next periodic feed tick.
  void setPriceOffset(String symbol, double offset) {
    if (!offset.isFinite) return;
    _offsets[symbol.toUpperCase()] = offset;
    _emitNow();
  }

  /// Recomputes every symbol's price using the current noise curve +
  /// offsets and broadcasts a fresh [LivePriceUpdate]. Bypasses the
  /// `_paused` short-circuit on [_emit] (we want debug-driven changes
  /// to be visible even while the feed is paused) but still respects
  /// `_disposed`.
  void _emitNow() {
    if (_disposed) return;
    final DateTime now = _clock.now();
    for (final MapEntry<String, PriceNoise> entry in _noises.entries) {
      final String symbol = entry.key;
      final PriceNoise noise = entry.value;
      final double base = noise.priceAt(now) + (_offsets[symbol] ?? 0);
      final double price = base.clamp(0.0001, double.infinity);
      _currentPrices[symbol] =
          double.parse(price.toStringAsFixed(_decimalsFor(price)));
    }
    if (_controller.isClosed) return;
    _controller.add(
      LivePriceUpdate(
        prices: Map<String, double>.unmodifiable(_currentPrices),
        timestamp: now,
      ),
    );
  }

  /// Pauses or resumes ALL tick generation. While paused, no events
  /// are emitted; resumption re-arms the timer immediately.
  void setPaused(bool paused) {
    if (_paused == paused) return;
    _paused = paused;
    if (!paused) _scheduleNextTick();
  }

  Future<void> dispose() async {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    if (!_controller.isClosed) await _controller.close();
  }
}
