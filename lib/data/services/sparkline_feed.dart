import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../core/clock/clock.dart';
import 'historical_price_api.dart';
import 'live_price_feed.dart';

/// Per-symbol rolling sparkline state published as a
/// [ValueListenable] for cheap, surgical UI updates.
///
/// Why a service (not a bloc): every visible row in the markets list
/// owns one mini-graph. Routing all of them through a bloc would mean
/// a bloc emit + tree rebuild for every list row on every tick, which
/// kills frame budget the moment the list gets long.
///
/// Instead, this service:
///   1. Subscribes **once** to [LivePriceFeed.watchAll].
///   2. Maintains one bounded ring buffer per symbol.
///   3. Hands each row a [ValueListenable<SparklineSnapshot>] for
///      *its* symbol.
///
/// Combined with `RepaintBoundary` around each sparkline widget,
/// only the rows that actually have new data repaint, and the price
/// row text never invalidates the sparkline (or vice versa).
///
/// Buffers are seeded by an **async fetch through the warehouse
/// [HistoricalPriceApi]** — the same surface the candlestick chart
/// pulls from, with the same simulated latency. While the fetch is
/// in flight the buffer's snapshot is in [SparklineSnapshot.loading]
/// state and the row should render a shimmer; once the response
/// resolves the snapshot flips to loaded with the downsampled shape.
/// Live ticks then append into the same buffer, so the row's curve
/// continues from the historical seed seamlessly.
///
/// The bloc/widget layer never reads historical data outside this
/// API surface — the [LivePriceFeed.priceAt] noise generator is
/// touched only inside [HistoricalPriceApi].
class SparklineFeed {
  SparklineFeed({
    required LivePriceFeed feed,
    required HistoricalPriceApi historicalApi,
    Clock clock = const SystemClock(),
    int bufferSize = 32,
    Duration historyWindow = const Duration(hours: 24),
  })  : _feed = feed,
        _historicalApi = historicalApi,
        _clock = clock,
        _bufferSize = bufferSize,
        _historyWindow = ValueNotifier<Duration>(historyWindow) {
    _subscription = _feed.watchAll().listen(_onPricesUpdated);
  }

  final LivePriceFeed _feed;
  final HistoricalPriceApi _historicalApi;
  final Clock _clock;
  final int _bufferSize;
  final ValueNotifier<Duration> _historyWindow;
  StreamSubscription<LivePriceUpdate>? _subscription;
  bool _disposed = false;

  /// Width of the trailing window each sparkline buffer represents.
  /// Exposed as a [ValueListenable] so debug UIs can both read the
  /// current value and rebuild when it changes (e.g. a stepper that
  /// shows "24h" / "7d" alongside +/- buttons).
  ValueListenable<Duration> get historyWindowListenable => _historyWindow;

  /// Current trailing window. Update via [setHistoryWindow].
  Duration get historyWindow => _historyWindow.value;

  /// Replace the trailing window. Re-seeds every existing buffer
  /// from the warehouse against the new range — buffers flip back
  /// into loading state (shimmer) until their re-fetch resolves so
  /// the UI never shows the previous window's points stretched
  /// across the new one.
  ///
  /// No-op if [value] equals the current window.
  void setHistoryWindow(Duration value) {
    if (_disposed) return;
    if (_historyWindow.value == value) return;
    _historyWindow.value = value;
    for (final MapEntry<String, _SparklineBuffer> entry in _buffers.entries) {
      entry.value.reset();
      unawaited(_seedFromWarehouse(entry.key, entry.value));
    }
  }

  /// Lookup table from upper-cased symbol → buffer. We don't evict;
  /// each buffer is `bufferSize` doubles wide (32 by default ≈ 256
  /// bytes), so even a few thousand symbols sit comfortably in
  /// memory.
  final Map<String, _SparklineBuffer> _buffers = <String, _SparklineBuffer>{};

  /// Returns the [ValueListenable] for [symbol]. Creates the buffer
  /// (in loading state) and dispatches a warehouse seed-fetch on
  /// first call. Subsequent calls return the same notifier instance
  /// so multiple widgets watching the same symbol share state.
  ValueListenable<SparklineSnapshot> watch(String symbol) {
    final String key = symbol.toUpperCase();
    return _buffers.putIfAbsent(key, () {
      final _SparklineBuffer buffer = _SparklineBuffer(_bufferSize);
      // Fire-and-forget: the buffer publishes its loaded snapshot
      // when the future resolves; nothing else awaits this.
      unawaited(_seedFromWarehouse(key, buffer));
      return buffer;
    });
  }

  /// Synchronous read of the current values for [symbol]. Useful for
  /// tests and debug overlays — UI should prefer [watch].
  List<double> currentValues(String symbol) {
    final _SparklineBuffer? buffer = _buffers[symbol.toUpperCase()];
    return buffer?.value.values ?? const <double>[];
  }

  /// Whether the seed fetch for [symbol] is still in flight. Always
  /// true before the first `watch(symbol)` call.
  bool isLoading(String symbol) {
    final _SparklineBuffer? buffer = _buffers[symbol.toUpperCase()];
    return buffer?.value.isLoading ?? true;
  }

  Future<void> _seedFromWarehouse(
    String key,
    _SparklineBuffer buffer,
  ) async {
    try {
      final DateTime now = _clock.now();
      final Duration window = _historyWindow.value;
      final DateTime start = now.subtract(window);

      // Specialized "sparkline samples" call: synth + downsample BOTH
      // run on a background isolate, so the only payload crossing
      // back to the main thread is the small `List<double>` — never
      // the intermediate ~30k Tick objects. With one fetch per
      // visible row this is the difference between a smooth markets
      // list and a stutter on tab switch.
      //
      // Past samples bake in `offsetAt(symbol, t)` — i.e. whatever
      // dial value was active at each historical timestamp (zero
      // for typical sessions where no past dial events exist).
      // Live ticks then update the rightmost value in place, so a
      // freshly-dialed offset shows up as a sharp right-edge jump
      // — the visual "the price just spiked" cue we want for the
      // mini sparkline.
      final List<double> samples =
          await _historicalApi.fetchSparklineSamples(
        symbol: key,
        start: start,
        end: now,
        sampleCount: _bufferSize,
      );
      if (_disposed) return;
      for (final double p in samples) {
        buffer.push(p);
      }
      buffer.markLoaded();
    } catch (_) {
      // Warehouse failure shouldn't leave the row shimmering
      // forever — flip to "loaded but empty" so the renderer just
      // shows a blank line; live ticks (if any arrive) will
      // populate the buffer naturally.
      if (!_disposed) buffer.markLoaded();
    }
  }

  void _onPricesUpdated(LivePriceUpdate update) {
    if (_disposed) return;
    // Only the buffers we've already created are interesting — we
    // don't want to spin up notifiers for every symbol the feed
    // happens to track. Iterating `_buffers` keeps per-tick work
    // proportional to what the UI is actually showing.
    for (final MapEntry<String, _SparklineBuffer> entry in _buffers.entries) {
      final String key = entry.key;
      final _SparklineBuffer buffer = entry.value;

      final double? price = update.prices[key];
      if (price == null) continue;
      // Replace the rightmost (most-recent) point in place rather
      // than appending. The buffer was seeded to span a full 1-day
      // window from the warehouse — appending on every tick would
      // drop the oldest seed point on each live update, degrading
      // the sparkline from "trailing 24h" to "last `bufferSize`
      // live ticks" within seconds. Replacing the rightmost keeps
      // the 24h shape intact while letting the right edge track
      // the current price.
      //
      // No anchor/baked-offset shifting: the seed values are the
      // historical noise curve at their original timestamps and
      // stay valid across debug dial events (the dial only
      // affects the present and future, not the past). A dial
      // event shows up naturally as a sharp right-edge jump on
      // the next tick.
      buffer.pushLive(price);
    }
    // Single coalesced notify per buffer at the end of the tick so
    // intra-tick pushes don't fan out into duplicate rebuilds.
    for (final _SparklineBuffer buffer in _buffers.values) {
      buffer.flush();
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    await _subscription?.cancel();
    _subscription = null;
    for (final _SparklineBuffer buffer in _buffers.values) {
      buffer.dispose();
    }
    _buffers.clear();
    _historyWindow.dispose();
  }
}

/// Snapshot a sparkline row paints.
///
/// While [isLoading] is `true` the row should render a shimmer
/// placeholder; once the warehouse fetch resolves [isLoading] flips
/// to `false` and [values] is populated with the historical seed
/// spanning a 1-day window. Subsequent live ticks update only the
/// rightmost value in place — keeping the sparkline anchored to its
/// trailing 24h shape rather than degrading into "last N live
/// ticks" once the buffer cycles. [isLoading] stays `false` after
/// hydration regardless of subsequent live tick activity.
class SparklineSnapshot {
  const SparklineSnapshot({required this.values, required this.isLoading});

  /// Sentinel snapshot used while the warehouse fetch is in flight.
  static const SparklineSnapshot loading = SparklineSnapshot(
    values: <double>[],
    isLoading: true,
  );

  final List<double> values;
  final bool isLoading;
}

/// Internal: a [ValueNotifier]-shaped fixed-capacity ring buffer.
///
/// `push` is `O(1)` amortized — it appends to a [Queue] and trims
/// the head when over capacity. `flush` snapshots the queue into an
/// immutable [SparklineSnapshot] (the value listeners receive) and
/// notifies; only the snapshot is exposed to the rest of the app.
class _SparklineBuffer extends ChangeNotifier
    implements ValueListenable<SparklineSnapshot> {
  _SparklineBuffer(this._capacity);

  final int _capacity;
  final Queue<double> _ring = Queue<double>();
  SparklineSnapshot _snapshot = SparklineSnapshot.loading;
  bool _dirty = false;
  bool _isLoaded = false;

  @override
  SparklineSnapshot get value => _snapshot;

  /// Appends [price] and trims the head if the ring is now over
  /// capacity. Used to fill the buffer with the warehouse seed
  /// during hydration. Live ticks should call [pushLive] instead so
  /// the rolling sparkline stays anchored to its 1-day window.
  void push(double price) {
    _ring.addLast(price);
    while (_ring.length > _capacity) {
      _ring.removeFirst();
    }
    _dirty = true;
  }

  /// Replaces the rightmost (most-recent) value in place with
  /// [price]. No-op if the ring is empty (we'll get the rightmost
  /// from the upcoming warehouse seed instead — replacing nothing
  /// would just create a single-tick line that the shimmer hides
  /// anyway).
  ///
  /// This is the live-tick semantic: once the buffer holds the
  /// trailing-24h shape, every live tick should nudge only the
  /// right edge. Pushing-and-trimming on each tick — the previous
  /// behavior — would burn through the historical seed in
  /// `bufferSize` ticks (~20s at default settings), turning the
  /// row's "1-day mini sparkline" into a noisy short-term trace.
  void pushLive(double price) {
    if (_ring.isEmpty) return;
    _ring.removeLast();
    _ring.addLast(price);
    _dirty = true;
  }

  /// Drops every sample and flips the buffer back into loading
  /// state. Used when the parent [SparklineFeed] needs to re-seed
  /// against a new window — the row shimmers until the warehouse
  /// re-fetch resolves rather than briefly showing stale points
  /// stretched across the new range.
  void reset() {
    _ring.clear();
    _isLoaded = false;
    _snapshot = SparklineSnapshot.loading;
    _dirty = false;
    notifyListeners();
  }

  /// Flips the buffer out of loading state and publishes whatever
  /// it currently holds. Called once per buffer by [SparklineFeed]
  /// when the warehouse seed fetch resolves (success or failure).
  void markLoaded() {
    if (_isLoaded) return;
    _isLoaded = true;
    _dirty = true;
    flush();
  }

  /// Publishes any pending changes. No-op when nothing was pushed
  /// since the previous flush — keeps spurious notifications off
  /// the wire.
  void flush() {
    if (!_dirty) return;
    _snapshot = SparklineSnapshot(
      values: List<double>.unmodifiable(_ring),
      isLoading: !_isLoaded,
    );
    _dirty = false;
    notifyListeners();
  }
}
