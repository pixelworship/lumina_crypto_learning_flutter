import 'dart:async';
import 'dart:math';

import '../../core/clock/clock.dart';
import '../models/crypto_asset.dart';
import 'asset_catalog.dart';
import 'price_noise.dart';

/// Single dial event in a symbol's offset history.
///
/// The [offset] takes effect AT [timestamp] and stays in force until
/// a later event supersedes it. Modeling the debug "price pump"
/// feature as a step function — rather than a single mutable value
/// applied uniformly to the entire timeline — is what makes it
/// behave like a real-world volume-driven spike: prices BEFORE the
/// press stay where they were (the past was the past), prices FROM
/// the press forward are at `noise(t) + offset`. Paging back through
/// history reveals the step at the exact moment of the press,
/// instead of seeing the entire historical curve uniformly slide
/// up/down with the dial.
typedef OffsetEvent = ({DateTime timestamp, double offset});

/// One emission of the live price feed: the full price map for every
/// registered symbol at a single point in time, plus the per-symbol
/// CURRENT debug offset value.
///
/// `prices` always reflects the logical price the rest of the app
/// should show — for live emissions that's `noise(now) +
/// offsetAt(symbol, now)`. `offsets` carries the per-symbol latest
/// dial value as informational metadata (e.g. so a debug overlay
/// can render the current dial position); subscribers should NOT
/// shift cached historical anchors in response to changes here.
/// With the event-based offset model, a historical anchor is
/// `noise(historicalTimestamp) + offsetAt(symbol,
/// historicalTimestamp)` and stays correct across debug dial events
/// because the offset that was active at the historical timestamp
/// doesn't change retroactively.
class LivePriceUpdate {
  const LivePriceUpdate({
    required this.prices,
    required this.offsets,
    required this.timestamp,
  });

  /// Live price per symbol. Reflects the current offset dialed for
  /// that symbol (if any).
  final Map<String, double> prices;

  /// Per-symbol latest debug dial value. Empty for symbols with no
  /// dial events. Informational only — see class doc.
  final Map<String, double> offsets;

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
    final DateTime now = _clock.now();
    final double price =
        (noise.priceAt(now) + _offsetAt(key, now))
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
      final double base = noise.priceAt(now) + _offsetAt(symbol, now);
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

  /// Per-symbol offset history, sorted ascending by timestamp.
  /// Lookups walk the list in order taking the latest event whose
  /// timestamp is `<= t`. Each [setPriceOffset] call APPENDS a new
  /// event rather than overwriting any single mutable value — so
  /// past prices keep whatever offset was in force at their original
  /// time, and only ticks from the dial moment forward see the new
  /// offset (modeling a real-world price-pump event where the past
  /// is the past).
  final Map<String, List<OffsetEvent>> _offsetEvents =
      <String, List<OffsetEvent>>{};

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

  /// Returns the offset that was active for [key] at time [t].
  /// Walks the symbol's event history and takes the latest event
  /// whose timestamp is `<= t`. Returns 0 when the dial has never
  /// been moved (or all recorded events are AFTER [t]).
  ///
  /// Linear walk because per-symbol event lists are tiny in
  /// practice (a handful of user dials per session) — a binary
  /// search would lose against the constant-factor savings of an
  /// in-cache linear scan at this size.
  double _offsetAt(String key, DateTime t) {
    final List<OffsetEvent>? events = _offsetEvents[key];
    if (events == null || events.isEmpty) return 0;
    double offset = 0;
    for (final OffsetEvent e in events) {
      if (e.timestamp.isAfter(t)) break;
      offset = e.offset;
    }
    return offset;
  }

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
      final double base = noise.priceAt(now) + _offsetAt(symbol, now);
      // Small per-tick jitter for tick-to-tick spread within a candle.
      final double jitter =
          (_random.nextDouble() - 0.5) * (base.abs() * 0.001);
      final double price = (base + jitter).clamp(0.0001, double.infinity);
      _currentPrices[symbol] =
          double.parse(price.toStringAsFixed(_decimalsFor(price)));
    }
    if (_controller.isClosed) return;
    _controller.add(_buildUpdate(now));
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
    final DateTime now = _clock.now();
    final double price = noise.priceAt(now) + _offsetAt(key, now);
    return double.parse(price.toStringAsFixed(_decimalsFor(price)));
  }

  /// Computes the price for [symbol] at an arbitrary [timestamp]
  /// using the symbol's noise curve, with the offset that was
  /// active AT [timestamp] baked in (NOT the current dial value).
  ///
  /// This is the key to making the debug-pump feature behave like a
  /// real-world spike rather than a uniform "everything slides
  /// together" shift: the API service uses [priceAt] to compute the
  /// 24h anchor (`CryptoQuote.priceAt24hAgo`,
  /// `BalanceSummary.valueAt24hAgo`, etc.). With the event-based
  /// model, a press dialed in JUST NOW does not retroactively shift
  /// yesterday's price — the anchor stays where it was, and the
  /// live tick at `now + offset` produces the visible step exactly
  /// at the moment of the press.
  double priceAt(String symbol, DateTime timestamp) {
    final String key = symbol.toUpperCase();
    final PriceNoise noise = _ensureNoise(key);
    final double price =
        noise.priceAt(timestamp) + _offsetAt(key, timestamp);
    return double.parse(price.toStringAsFixed(_decimalsFor(price)));
  }

  /// Direct access to the [PriceNoise] for a symbol — used by the
  /// chart's history repositories so historical ticks share the same
  /// curve as live ticks. Lazily creates the generator for symbols
  /// the feed hasn't seen before (so a chart opened on a paginated
  /// asset works without pre-registration).
  PriceNoise? noiseFor(String symbol) => _ensureNoise(symbol);

  /// Current (latest-dialed) debug offset for [symbol]. Returns 0
  /// when the dial has never been moved for this symbol.
  ///
  /// Note: this is the LATEST dial value, which is also the offset
  /// that applies to ticks AT or AFTER the latest dial event — i.e.
  /// the value live ticks emerging right now will use. To compute
  /// the offset that was active at an arbitrary historical
  /// timestamp, use [priceAt] directly (which internally calls
  /// [_offsetAt]) rather than reading this and subtracting.
  double priceOffset(String symbol) {
    final List<OffsetEvent>? events = _offsetEvents[symbol.toUpperCase()];
    if (events == null || events.isEmpty) return 0;
    return events.last.offset;
  }

  /// Returns the full offset event history for [symbol], sorted
  /// ascending by timestamp. Used by [MockHistoricalPriceApi] so
  /// each synthesized tick can pick up the offset that was active
  /// at THAT tick's timestamp (not the current dial position).
  ///
  /// Returns an unmodifiable view — callers must not mutate.
  List<OffsetEvent> offsetEvents(String symbol) {
    final List<OffsetEvent>? events = _offsetEvents[symbol.toUpperCase()];
    if (events == null) return const <OffsetEvent>[];
    return List<OffsetEvent>.unmodifiable(events);
  }

  /// Multiplies the base emission frequency. Values greater than 1
  /// emit ticks faster, less than 1 slower. Must be > 0.
  void setSpeedMultiplier(double multiplier) {
    if (multiplier <= 0 || !multiplier.isFinite) return;
    _speedMultiplier = multiplier;
  }

  /// Records a dial event for [symbol] at the current wall clock.
  ///
  /// The event is APPENDED to the symbol's offset history rather
  /// than overwriting any single mutable value — so prices BEFORE
  /// the dial keep whatever offset was in force at their original
  /// time, and only ticks FROM the dial moment forward see the new
  /// offset. Visually this renders as a clean step at the moment
  /// of the press, just like a real-world volume-driven price
  /// pump (the chart, the markets row, the portfolio, the trade
  /// card header) instead of the entire historical curve sliding
  /// up/down with the dial.
  ///
  /// Triggers an immediate broadcast so every subscriber snaps to
  /// the new live price on the next frame — without waiting for
  /// the next periodic feed tick.
  ///
  /// Calling with `offset == 0` is treated as a fresh "dial back to
  /// zero" event: prices from this moment forward return to the
  /// underlying noise curve, but prices BETWEEN earlier dial
  /// events stay at whatever offset was active during that window.
  void setPriceOffset(String symbol, double offset) {
    if (!offset.isFinite) return;
    final String key = symbol.toUpperCase();
    final DateTime now = _clock.now();
    _offsetEvents
        .putIfAbsent(key, () => <OffsetEvent>[])
        .add((timestamp: now, offset: offset));
    _emitNow(at: now);
  }

  /// Recomputes every symbol's price using the current noise curve +
  /// offset events and broadcasts a fresh [LivePriceUpdate].
  /// Bypasses the [_paused] short-circuit on [_emit] (we want
  /// debug-driven changes to be visible even while the feed is
  /// paused) but still respects [_disposed].
  ///
  /// [at] lets callers pin the broadcast timestamp to the same
  /// wall clock instant as the dial event (so the event timestamp
  /// and the broadcast timestamp can't drift even on a real-clock
  /// scheduler with sub-microsecond jitter).
  void _emitNow({DateTime? at}) {
    if (_disposed) return;
    final DateTime now = at ?? _clock.now();
    for (final MapEntry<String, PriceNoise> entry in _noises.entries) {
      final String symbol = entry.key;
      final PriceNoise noise = entry.value;
      final double base = noise.priceAt(now) + _offsetAt(symbol, now);
      final double price = base.clamp(0.0001, double.infinity);
      _currentPrices[symbol] =
          double.parse(price.toStringAsFixed(_decimalsFor(price)));
    }
    if (_controller.isClosed) return;
    _controller.add(_buildUpdate(now));
  }

  /// Builds a [LivePriceUpdate] from the current price cache + the
  /// latest offset for each symbol that has a dial history. Shared
  /// between the periodic [_emit] and the on-demand [_emitNow] so
  /// both broadcast shapes stay in lockstep.
  LivePriceUpdate _buildUpdate(DateTime now) {
    final Map<String, double> latestOffsets = <String, double>{
      for (final MapEntry<String, List<OffsetEvent>> e
          in _offsetEvents.entries)
        if (e.value.isNotEmpty) e.key: e.value.last.offset,
    };
    return LivePriceUpdate(
      prices: Map<String, double>.unmodifiable(_currentPrices),
      offsets: Map<String, double>.unmodifiable(latestOffsets),
      timestamp: now,
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
