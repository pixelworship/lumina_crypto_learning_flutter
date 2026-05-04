import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../core/clock/clock.dart';
import 'live_price_feed.dart';

/// Immutable per-symbol rolling sparkline buffer published as a
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
///   3. Hands each row a [ValueListenable] for *its* symbol.
///
/// Combined with `RepaintBoundary` around each sparkline widget,
/// only the rows that actually have new data repaint, and the price
/// row text never invalidates the sparkline (or vice versa).
///
/// Buffers are pre-seeded from the same noise curve the live feed
/// uses ([LivePriceFeed.priceAt]) so a sparkline shows up filled in
/// the very first frame — no "flat line until first tick" flicker.
class SparklineFeed {
  SparklineFeed({
    required LivePriceFeed feed,
    Clock clock = const SystemClock(),
    int bufferSize = 32,
    Duration seedInterval = const Duration(seconds: 30),
  })  : _feed = feed,
        _clock = clock,
        _bufferSize = bufferSize,
        _seedInterval = seedInterval {
    _subscription = _feed.watchAll().listen(_onPricesUpdated);
  }

  final LivePriceFeed _feed;
  final Clock _clock;
  final int _bufferSize;
  final Duration _seedInterval;
  StreamSubscription<LivePriceUpdate>? _subscription;
  bool _disposed = false;

  /// Lookup table from upper-cased symbol → buffer. We don't evict;
  /// each buffer is `bufferSize` doubles wide (32 by default ≈ 256
  /// bytes), so even a few thousand symbols sit comfortably in
  /// memory.
  final Map<String, _SparklineBuffer> _buffers = <String, _SparklineBuffer>{};

  /// Returns the [ValueListenable] for [symbol]. Creates and seeds
  /// the buffer on first call. Subsequent calls return the same
  /// notifier instance so multiple widgets watching the same symbol
  /// share state.
  ValueListenable<List<double>> watch(String symbol) {
    final String key = symbol.toUpperCase();
    return _buffers.putIfAbsent(key, () => _seedBuffer(key));
  }

  /// Synchronous read of the current buffer for [symbol]. Useful for
  /// tests and debug overlays — UI should prefer [watch].
  List<double> currentValues(String symbol) {
    final _SparklineBuffer? buffer = _buffers[symbol.toUpperCase()];
    return buffer?.value ?? const <double>[];
  }

  _SparklineBuffer _seedBuffer(String key) {
    final _SparklineBuffer buffer = _SparklineBuffer(_bufferSize);
    final DateTime now = _clock.now();
    // Sample evenly across the past so the seeded shape matches
    // whatever the noise curve was doing — when live ticks arrive
    // they'll continue from that same curve seamlessly.
    for (int i = _bufferSize - 1; i >= 0; i--) {
      final DateTime t = now.subtract(_seedInterval * i);
      buffer.push(_feed.priceAt(key, t));
    }
    buffer.flush();
    return buffer;
  }

  void _onPricesUpdated(LivePriceUpdate update) {
    if (_disposed) return;
    // Only the buffers we've already created are interesting — we
    // don't want to spin up notifiers for every symbol the feed
    // happens to track. Iterating `_buffers` keeps per-tick work
    // proportional to what the UI is actually showing.
    for (final MapEntry<String, _SparklineBuffer> entry in _buffers.entries) {
      final double? price = update.prices[entry.key];
      if (price == null) continue;
      entry.value.push(price);
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
  }
}

/// Internal: a [ValueNotifier]-shaped fixed-capacity ring buffer.
///
/// `push` is `O(1)` amortized — it appends to a [Queue] and trims
/// the head when over capacity. `flush` snapshots the queue into an
/// immutable list (the value listeners receive) and notifies; only
/// the snapshot is exposed to the rest of the app.
class _SparklineBuffer extends ChangeNotifier
    implements ValueListenable<List<double>> {
  _SparklineBuffer(this._capacity);

  final int _capacity;
  final Queue<double> _ring = Queue<double>();
  List<double> _snapshot = const <double>[];
  bool _dirty = false;

  @override
  List<double> get value => _snapshot;

  void push(double price) {
    _ring.addLast(price);
    while (_ring.length > _capacity) {
      _ring.removeFirst();
    }
    _dirty = true;
  }

  /// Publishes any pending changes. No-op when nothing was pushed
  /// since the previous flush — keeps spurious notifications off
  /// the wire.
  void flush() {
    if (!_dirty) return;
    _snapshot = List<double>.unmodifiable(_ring);
    _dirty = false;
    notifyListeners();
  }
}
