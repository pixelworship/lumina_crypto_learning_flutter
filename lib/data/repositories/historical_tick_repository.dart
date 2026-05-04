import '../../core/diagnostics/mrm_trace.dart';
import '../models/tick.dart';
import '../services/historical_price_api.dart';
import '../services/historical_tick_cache.dart';

/// Repository abstraction over per-asset historical tick storage.
///
/// Strictly date-range queries — no streaming, no implicit "current"
/// time. The chart calls into this for initial history, for
/// paginated history extension (load older), and for pause-gap
/// backfill. All three use the same single method.
abstract class HistoricalTickRepository {
  /// Returns ticks for [symbol] over the closed-open interval
  /// `[start, end)`. Implementations are free to serve cached data
  /// where available — callers should not assume a network round
  /// trip on every call.
  Future<List<Tick>> fetchTicks({
    required String symbol,
    required DateTime start,
    required DateTime end,
  });

  /// Synchronously returns whatever ticks are already cached for
  /// [symbol] over `[start, end)`. Never hits the network.
  ///
  /// Used by callers that want to render *something* immediately
  /// (e.g. when switching between assets) and then call
  /// [fetchTicks] in the background to fill the gap. An empty
  /// return means there's nothing cached for this symbol+range —
  /// fall back to the loading state.
  List<Tick> peekTicks({
    required String symbol,
    required DateTime start,
    required DateTime end,
  });

  /// Drops any cached ticks for [symbol]. Callers invoke this when
  /// they know the underlying price curve has shifted (e.g. a
  /// debug-driven price offset) so the next [fetchTicks] call
  /// pulls fresh, offset-baked data instead of serving stale ticks
  /// from the cache.
  void invalidate(String symbol);
}

/// Production-shape repository: cache-first, API-fallback.
///
/// Flow on every [fetchTicks] call:
///
/// 1. Ask the [HistoricalTickCache] what it has for the requested
///    interval. The cache returns a list of already-stored ticks
///    (`hits`) plus any sub-ranges it doesn't know about
///    (`missing`).
/// 2. Issue one API call per missing range. (Real backends would let
///    us batch, but the per-range loop also gives a natural place to
///    add per-page cancellation later.)
/// 3. Feed every fetched range back into the cache so the next
///    request for the same interval is free.
/// 4. Merge cache hits + freshly fetched ticks, sort by timestamp,
///    and return.
///
/// The repository is stateless — the cache is owned by the app
/// (registered as a [RepositoryProvider]) so two repository
/// instances would share the same warm cache.
class CachedHistoricalTickRepository implements HistoricalTickRepository {
  CachedHistoricalTickRepository({
    required HistoricalPriceApi api,
    required HistoricalTickCache cache,
  }) : _api = api,
       _cache = cache;

  final HistoricalPriceApi _api;
  final HistoricalTickCache _cache;

  @override
  Future<List<Tick>> fetchTicks({
    required String symbol,
    required DateTime start,
    required DateTime end,
  }) async {
    MrmTrace.mark(50, 'Repo.fetchTicks start', 'symbol=$symbol');
    if (!end.isAfter(start)) return const <Tick>[];

    final CacheLookup lookup = _cache.lookup(
      symbol: symbol,
      start: start,
      end: end,
    );
    MrmTrace.mark(51, 'Repo cache lookup',
        'hits=${lookup.hits.length} missing=${lookup.missing.length}');
    if (lookup.missing.isEmpty) {
      MrmTrace.mark(56, 'Repo.fetchTicks done (full cache hit)',
          'ticks=${lookup.hits.length}');
      return lookup.hits;
    }

    final List<Tick> fetched = <Tick>[];
    for (final TickRange range in lookup.missing) {
      MrmTrace.mark(52, 'Repo.api.fetchTicks await',
          'range=${range.start.toIso8601String()}..${range.end.toIso8601String()}');
      final List<Tick> ticks = await _api.fetchTicks(
        symbol: symbol,
        start: range.start,
        end: range.end,
      );
      MrmTrace.mark(53, 'Repo.api.fetchTicks done', 'ticks=${ticks.length}');
      // Store each page individually so the covered-ranges metadata
      // accurately reflects which intervals we've asked about.
      _cache.store(
        symbol: symbol,
        ticks: ticks,
        rangeStart: range.start,
        rangeEnd: range.end,
      );
      MrmTrace.mark(54, 'Repo cache store');
      fetched.addAll(ticks);
    }

    final List<Tick> merged = <Tick>[...lookup.hits, ...fetched]
      ..sort((Tick a, Tick b) => a.timestamp.compareTo(b.timestamp));
    MrmTrace.mark(55, 'Repo.fetchTicks merge+sort done',
        'ticks=${merged.length}');
    return merged;
  }

  @override
  List<Tick> peekTicks({
    required String symbol,
    required DateTime start,
    required DateTime end,
  }) {
    if (!end.isAfter(start)) return const <Tick>[];
    return _cache.lookup(symbol: symbol, start: start, end: end).hits;
  }

  @override
  void invalidate(String symbol) => _cache.invalidate(symbol);
}
