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

    // Each fetched range is itself sorted ascending (api contract).
    // We accumulate the per-range fetches as a list-of-sorted-runs so
    // we can merge against `lookup.hits` in linear time below.
    final List<List<Tick>> fetchedRuns = <List<Tick>>[];
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
      // accurately reflects which intervals we've asked about. The
      // cache itself merges incoming sorted runs in O(n+m) — see
      // [_SymbolCache._mergeSorted].
      _cache.store(
        symbol: symbol,
        ticks: ticks,
        rangeStart: range.start,
        rangeEnd: range.end,
      );
      MrmTrace.mark(54, 'Repo cache store');
      if (ticks.isNotEmpty) fetchedRuns.add(ticks);
    }

    // K-way merge of pre-sorted runs (`lookup.hits` plus every fetched
    // range). The previous implementation did a single big
    // `..sort()` after concatenation — `O((n+m) log(n+m))` on the main
    // thread, which adds up fast on a 24h fetch (~30k+ ticks per
    // page). Linear merging keeps the work proportional to the
    // payload and stays in the main thread without dropping frames.
    final List<List<Tick>> runs = <List<Tick>>[
      if (lookup.hits.isNotEmpty) lookup.hits,
      ...fetchedRuns,
    ];
    final List<Tick> merged = _mergeSortedRuns(runs);
    MrmTrace.mark(55, 'Repo.fetchTicks merge done', 'ticks=${merged.length}');
    return merged;
  }

  /// K-way merge over pre-sorted tick runs. Linear in total size
  /// when the run count is small (which it always is here — at most
  /// `cacheHits + missingRanges + 1`, typically 1–2). For larger run
  /// counts we'd want a proper min-heap; we don't have that case in
  /// practice so the straightforward "find the minimum head" loop
  /// stays cache-friendly.
  static List<Tick> _mergeSortedRuns(List<List<Tick>> runs) {
    if (runs.isEmpty) return const <Tick>[];
    if (runs.length == 1) return List<Tick>.from(runs.first);
    int total = 0;
    for (final List<Tick> run in runs) {
      total += run.length;
    }
    if (total == 0) return const <Tick>[];
    final List<int> idx = List<int>.filled(runs.length, 0);
    final List<Tick> out = List<Tick>.filled(total, runs.first.first,
        growable: true);
    for (int written = 0; written < total; written++) {
      int minRun = -1;
      DateTime? minTs;
      for (int r = 0; r < runs.length; r++) {
        if (idx[r] >= runs[r].length) continue;
        final DateTime ts = runs[r][idx[r]].timestamp;
        if (minTs == null || ts.isBefore(minTs)) {
          minTs = ts;
          minRun = r;
        }
      }
      out[written] = runs[minRun][idx[minRun]++];
    }
    return out;
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
