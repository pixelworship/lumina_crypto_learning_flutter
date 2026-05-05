import 'dart:collection';

import '../models/tick.dart';

/// Closed-open time interval `[start, end)`.
///
/// Lives next to [HistoricalTickCache] (rather than reusing
/// `package:flutter`'s `DateTimeRange`) so the cache layer doesn't
/// pull in a flutter dependency.
class TickRange {
  const TickRange({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  Duration get duration => end.difference(start);

  bool overlapsOrTouches(TickRange other) =>
      !end.isBefore(other.start) && !start.isAfter(other.end);

  TickRange merge(TickRange other) => TickRange(
    start: start.isBefore(other.start) ? start : other.start,
    end: end.isAfter(other.end) ? end : other.end,
  );

  @override
  String toString() => 'TickRange($start..$end)';
}

/// The result of asking the cache "what do you have for
/// `[start, end)` of [symbol]?". The repository serves [hits]
/// instantly and only goes to the historical API for [missing]
/// sub-ranges.
class CacheLookup {
  const CacheLookup({required this.hits, required this.missing});

  final List<Tick> hits;
  final List<TickRange> missing;
}

/// In-memory cache of recently-fetched historical ticks.
///
/// Two eviction policies layered together:
///
/// 1. **Symbol LRU** — at most [maxSymbols] symbols are kept; the
///    least-recently-accessed one is dropped when a new symbol is
///    added past the limit. Touching a symbol via [lookup] or [store]
///    bumps it to most-recently-used. (Implemented via
///    [LinkedHashMap]'s insertion-order semantics — we re-insert on
///    access.)
///
/// 2. **Per-symbol time window** — each symbol holds at most
///    [retentionPerSymbol] of data span. When a [store] would push a
///    symbol over that limit, the oldest covered range (and its
///    ticks) are dropped first.
///
/// Together this caps the cache at roughly
/// `maxSymbols * retentionPerSymbol` worth of data, regardless of
/// usage patterns.
class HistoricalTickCache {
  HistoricalTickCache({
    this.maxSymbols = 50,
    this.retentionPerSymbol = const Duration(days: 2),
  });

  /// LRU bound on number of distinct symbols held.
  final int maxSymbols;

  /// Maximum total data span retained per symbol.
  final Duration retentionPerSymbol;

  /// Insertion order = LRU order. Most-recently-touched symbols sit
  /// at the tail, oldest at the head.
  final LinkedHashMap<String, _SymbolCache> _symbols =
      LinkedHashMap<String, _SymbolCache>();

  /// Returns the ticks already in the cache that fall within
  /// `[start, end)` for [symbol], plus the list of sub-ranges the
  /// cache is missing. The repository is responsible for fetching
  /// the missing ranges from the historical API and feeding them
  /// back via [store].
  ///
  /// Touches [symbol] (bumps to MRU) regardless of hit/miss.
  CacheLookup lookup({
    required String symbol,
    required DateTime start,
    required DateTime end,
  }) {
    final _SymbolCache? cache = _touch(symbol);
    if (cache == null) {
      return CacheLookup(
        hits: const <Tick>[],
        missing: <TickRange>[TickRange(start: start, end: end)],
      );
    }
    return cache.query(start, end);
  }

  /// Records [ticks] for [symbol] over the closed-open interval
  /// `[start, end)`. The interval is required (rather than inferred
  /// from min/max tick timestamp) so contiguous ranges with no
  /// in-between ticks still register as covered — the cache won't
  /// re-ask the API for an empty interval.
  ///
  /// Evicts oldest data + ranges if the symbol is now over the
  /// retention window. Promotes [symbol] to MRU; evicts the LRU
  /// symbol if total symbols exceeds [maxSymbols].
  void store({
    required String symbol,
    required List<Tick> ticks,
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) {
    final _SymbolCache cache = _touch(symbol) ?? _create(symbol);
    cache.add(
      ticks: ticks,
      range: TickRange(start: rangeStart, end: rangeEnd),
    );
    cache.evictExcess(retentionPerSymbol);
  }

  /// Total number of symbols currently held.
  int get symbolCount => _symbols.length;

  /// Total number of cached ticks across all symbols. Mostly useful
  /// for tests and diagnostics.
  int get tickCount => _symbols.values.fold<int>(
    0,
    (int sum, _SymbolCache c) => sum + c.tickCount,
  );

  /// Drops everything. Used in tests + on logout / language change /
  /// any scenario where stale prices would be confusing.
  void clear() => _symbols.clear();

  /// Drops every cached range and tick for [symbol]. Used when
  /// something invalidates previously-cached prices for that asset
  /// (e.g. a debug-driven price offset change shifts the entire
  /// price curve, so cached ticks that bake in the OLD offset are
  /// no longer accurate). The next [lookup] for [symbol] will
  /// report everything as missing, prompting a fresh fetch.
  void invalidate(String symbol) {
    _symbols.remove(symbol.toUpperCase());
  }

  // ---------------------------------------------------------------------------
  // LRU helpers
  // ---------------------------------------------------------------------------

  _SymbolCache? _touch(String symbol) {
    final String key = symbol.toUpperCase();
    final _SymbolCache? cache = _symbols.remove(key);
    if (cache == null) return null;
    _symbols[key] = cache; // re-insert at the tail
    return cache;
  }

  _SymbolCache _create(String symbol) {
    final String key = symbol.toUpperCase();
    while (_symbols.length >= maxSymbols) {
      // Evict least-recently-used symbol (head of insertion order).
      _symbols.remove(_symbols.keys.first);
    }
    final _SymbolCache cache = _SymbolCache();
    _symbols[key] = cache;
    return cache;
  }
}

/// Per-symbol view: a sorted tick list + a list of merged covered
/// ranges. Ticks may be sparse within a covered range (the cache
/// layer doesn't try to enforce density), but a covered range
/// guarantees the API has been asked about that interval already.
class _SymbolCache {
  /// Sorted ascending by timestamp.
  final List<Tick> _ticks = <Tick>[];

  /// Sorted, non-overlapping covered ranges.
  final List<TickRange> _coveredRanges = <TickRange>[];

  int get tickCount => _ticks.length;

  CacheLookup query(DateTime start, DateTime end) {
    final List<Tick> hits = <Tick>[];
    for (final Tick t in _ticks) {
      if (t.timestamp.isBefore(start)) continue;
      if (!t.timestamp.isBefore(end)) break;
      hits.add(t);
    }
    return CacheLookup(hits: hits, missing: _diffMissing(start, end));
  }

  void add({required List<Tick> ticks, required TickRange range}) {
    if (ticks.isNotEmpty) {
      // Both `_ticks` and `ticks` are already sorted ascending by
      // timestamp (the cache invariant + the api's contract). A
      // linear two-way merge is O(n + m); the previous addAll+sort
      // was O((n + m) log(n + m)) — measurably worse on the main
      // thread once a symbol has accumulated a few warm pages
      // (~30k+ ticks per page). Doing this on the main thread is
      // fine at O(n) since memory bandwidth, not comparison count,
      // is the bottleneck for sorted-list merges.
      //
      // Compute the merged list BEFORE touching `_ticks` — the
      // cascade `..clear()..addAll(_mergeSorted(_ticks, ticks))`
      // would evaluate `clear` first and then call `_mergeSorted`
      // against an already-empty `_ticks`, dropping every existing
      // entry.
      final List<Tick> merged = _mergeSorted(_ticks, ticks);
      _ticks
        ..clear()
        ..addAll(merged);
    }
    _coveredRanges.add(range);
    _mergeRanges();
  }

  /// Two-way merge of pre-sorted tick lists (ascending by timestamp).
  /// Stable: ticks sharing a timestamp keep their `a`-before-`b`
  /// relative order, matching what `List.sort` would do for our
  /// equality-by-timestamp comparator.
  static List<Tick> _mergeSorted(List<Tick> a, List<Tick> b) {
    if (a.isEmpty) return List<Tick>.from(b);
    if (b.isEmpty) return List<Tick>.from(a);
    final List<Tick> merged = List<Tick>.filled(
      a.length + b.length,
      a.first,
      growable: true,
    );
    int i = 0;
    int j = 0;
    int k = 0;
    while (i < a.length && j < b.length) {
      if (b[j].timestamp.isBefore(a[i].timestamp)) {
        merged[k++] = b[j++];
      } else {
        merged[k++] = a[i++];
      }
    }
    while (i < a.length) {
      merged[k++] = a[i++];
    }
    while (j < b.length) {
      merged[k++] = b[j++];
    }
    return merged;
  }

  /// Trims the cache so the total covered span doesn't exceed
  /// [maxSpan]. Drops the OLDEST ranges + ticks first — the chart
  /// is biased toward recent data, so dropping ancient slices first
  /// keeps the most-likely-needed data warm.
  void evictExcess(Duration maxSpan) {
    Duration totalSpan = _coveredRanges.fold(
      Duration.zero,
      (Duration sum, TickRange r) => sum + r.duration,
    );
    while (totalSpan > maxSpan && _coveredRanges.isNotEmpty) {
      final TickRange oldest = _coveredRanges.removeAt(0);
      totalSpan -= oldest.duration;
      _ticks.removeWhere(
        (Tick t) =>
            !t.timestamp.isBefore(oldest.start) &&
            t.timestamp.isBefore(oldest.end),
      );
    }
  }

  /// Merges overlapping / touching ranges into a minimal sorted set.
  void _mergeRanges() {
    if (_coveredRanges.length < 2) return;
    _coveredRanges.sort(
      (TickRange a, TickRange b) => a.start.compareTo(b.start),
    );
    final List<TickRange> merged = <TickRange>[_coveredRanges.first];
    for (int i = 1; i < _coveredRanges.length; i++) {
      final TickRange last = merged.last;
      final TickRange cur = _coveredRanges[i];
      if (last.overlapsOrTouches(cur)) {
        merged[merged.length - 1] = last.merge(cur);
      } else {
        merged.add(cur);
      }
    }
    _coveredRanges
      ..clear()
      ..addAll(merged);
  }

  /// Returns the sub-intervals of `[start, end)` that are NOT
  /// covered by any range in [_coveredRanges].
  List<TickRange> _diffMissing(DateTime start, DateTime end) {
    if (!end.isAfter(start)) return const <TickRange>[];
    if (_coveredRanges.isEmpty) {
      return <TickRange>[TickRange(start: start, end: end)];
    }
    final List<TickRange> missing = <TickRange>[];
    DateTime cursor = start;
    for (final TickRange covered in _coveredRanges) {
      if (!covered.end.isAfter(cursor)) continue;
      if (!covered.start.isBefore(end)) break;
      if (covered.start.isAfter(cursor)) {
        final DateTime gapEnd =
            covered.start.isBefore(end) ? covered.start : end;
        missing.add(TickRange(start: cursor, end: gapEnd));
      }
      cursor = covered.end;
      if (!cursor.isBefore(end)) return missing;
    }
    if (cursor.isBefore(end)) {
      missing.add(TickRange(start: cursor, end: end));
    }
    return missing;
  }
}
