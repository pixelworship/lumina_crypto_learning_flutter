import 'dart:math';

import '../models/tick.dart';
import '../services/live_price_feed.dart';

/// Repository abstraction over a per-asset live tick stream.
///
/// BLoCs depend on this interface, not the concrete implementation, so
/// we can swap the mock generator for a real websocket-backed feed
/// without touching the presentation layer.
abstract class TickRepository {
  /// Streams ticks for [symbol]. Returning a hot stream is acceptable
  /// — ticks emitted before the listener attached are simply dropped.
  Stream<Tick> watchTicks(String symbol);

  /// Multiplies the base emission frequency. Values greater than 1
  /// emit ticks faster, values less than 1 slower. Must be > 0.
  void setSpeedMultiplier(double multiplier);

  /// Adds a constant price offset on top of the underlying price source
  /// for a single symbol. Useful for debug-driven price shocks.
  void setPriceOffset(String symbol, double offset);

  /// Returns the current debug-driven price offset for [symbol]
  /// (default 0). Exposed so callers that own per-bloc copies of the
  /// offset (e.g. the chart bloc) can seed their state from the
  /// shared feed's actual value — otherwise a route-scoped bloc
  /// constructed after the user already dialed an offset would think
  /// the offset is 0 while the feed reports a non-zero value, causing
  /// the next dial to overwrite (rather than increment) the feed's
  /// offset.
  double priceOffset(String symbol);

  /// Pauses or resumes tick generation entirely. While paused, no
  /// ticks are emitted — wall-clock time keeps advancing so resumption
  /// produces a real time gap (the chart marks it "DATA UNAVAILABLE").
  void setPaused(bool paused);

  Future<void> dispose();
}

/// Thin wrapper around [LivePriceFeed] that turns the unified price
/// stream into per-symbol [Tick]s for the candlestick chart.
///
/// The feed is owned by the app (so all consumers share it) — the
/// repository's `dispose()` is a no-op for that reason.
class MockTickRepository implements TickRepository {
  MockTickRepository({required LivePriceFeed feed, Random? random})
    : _feed = feed,
      _random = random ?? Random();

  final LivePriceFeed _feed;
  final Random _random;

  @override
  Stream<Tick> watchTicks(String symbol) {
    final String key = symbol.toUpperCase();
    return _feed.watchAll().map((LivePriceUpdate update) {
      final double price =
          update.prices[key] ?? _feed.currentPrice(key);
      return Tick(
        price: price,
        side: _random.nextBool() ? TickSide.buy : TickSide.sell,
        volume: (_random.nextInt(50) + 1).toDouble(),
        timestamp: update.timestamp,
      );
    });
  }

  @override
  void setSpeedMultiplier(double multiplier) =>
      _feed.setSpeedMultiplier(multiplier);

  @override
  void setPriceOffset(String symbol, double offset) =>
      _feed.setPriceOffset(symbol, offset);

  @override
  double priceOffset(String symbol) => _feed.priceOffset(symbol);

  @override
  void setPaused(bool paused) => _feed.setPaused(paused);

  @override
  Future<void> dispose() async {
    // The feed is owned by the app, not by the repository.
  }
}
