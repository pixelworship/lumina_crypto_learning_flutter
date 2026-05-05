import 'package:flutter_demo/data/models/tick.dart';
import 'package:flutter_demo/data/services/historical_tick_cache.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime _at(int hour) => DateTime.utc(2026, 5, 3, hour);

Tick _tick(int hour, {double price = 100}) => Tick(
  price: price,
  side: TickSide.buy,
  volume: 1,
  timestamp: _at(hour),
);

void main() {
  group('HistoricalTickCache', () {
    group('lookup on an empty cache', () {
      test('returns the entire range as missing and zero hits', () {
        final HistoricalTickCache cache = HistoricalTickCache();
        final CacheLookup result = cache.lookup(
          symbol: 'BTC',
          start: _at(0),
          end: _at(10),
        );
        expect(result.hits, isEmpty);
        expect(result.missing, hasLength(1));
        expect(result.missing.first.start, _at(0));
        expect(result.missing.first.end, _at(10));
      });
    });

    group('lookup after a store', () {
      test('serves a fully covered range straight from cache', () {
        final HistoricalTickCache cache = HistoricalTickCache();
        cache.store(
          symbol: 'BTC',
          ticks: <Tick>[_tick(2), _tick(4), _tick(6)],
          rangeStart: _at(0),
          rangeEnd: _at(10),
        );

        final CacheLookup result = cache.lookup(
          symbol: 'BTC',
          start: _at(2),
          end: _at(8),
        );
        expect(result.missing, isEmpty);
        expect(
          result.hits.map((Tick t) => t.timestamp.hour).toList(),
          <int>[2, 4, 6],
        );
      });

      test('reports the un-covered prefix and suffix as missing', () {
        final HistoricalTickCache cache = HistoricalTickCache();
        cache.store(
          symbol: 'BTC',
          ticks: <Tick>[_tick(5)],
          rangeStart: _at(4),
          rangeEnd: _at(6),
        );

        final CacheLookup result = cache.lookup(
          symbol: 'BTC',
          start: _at(2),
          end: _at(8),
        );
        expect(result.hits.map((Tick t) => t.timestamp.hour), <int>[5]);
        expect(result.missing, hasLength(2));
        expect(result.missing[0].start, _at(2));
        expect(result.missing[0].end, _at(4));
        expect(result.missing[1].start, _at(6));
        expect(result.missing[1].end, _at(8));
      });

      test('merges adjacent stored ranges so the gap between disappears', () {
        final HistoricalTickCache cache = HistoricalTickCache();
        cache.store(
          symbol: 'BTC',
          ticks: <Tick>[_tick(1)],
          rangeStart: _at(0),
          rangeEnd: _at(2),
        );
        cache.store(
          symbol: 'BTC',
          ticks: <Tick>[_tick(3)],
          rangeStart: _at(2),
          rangeEnd: _at(4),
        );

        final CacheLookup result = cache.lookup(
          symbol: 'BTC',
          start: _at(0),
          end: _at(4),
        );
        expect(result.missing, isEmpty);
        expect(result.hits.map((Tick t) => t.timestamp.hour), <int>[1, 3]);
      });

      test(
        'two stores with a real gap leave the gap as missing on lookup',
        () {
          final HistoricalTickCache cache = HistoricalTickCache();
          cache.store(
            symbol: 'BTC',
            ticks: <Tick>[_tick(1)],
            rangeStart: _at(0),
            rangeEnd: _at(2),
          );
          cache.store(
            symbol: 'BTC',
            ticks: <Tick>[_tick(7)],
            rangeStart: _at(6),
            rangeEnd: _at(8),
          );

          final CacheLookup result = cache.lookup(
            symbol: 'BTC',
            start: _at(0),
            end: _at(8),
          );
          expect(result.hits.map((Tick t) => t.timestamp.hour), <int>[1, 7]);
          expect(result.missing, hasLength(1));
          expect(result.missing.first.start, _at(2));
          expect(result.missing.first.end, _at(6));
        },
      );

      test('lookup is case-insensitive on symbol', () {
        final HistoricalTickCache cache = HistoricalTickCache();
        cache.store(
          symbol: 'btc',
          ticks: <Tick>[_tick(2)],
          rangeStart: _at(0),
          rangeEnd: _at(4),
        );
        final CacheLookup result = cache.lookup(
          symbol: 'BTC',
          start: _at(0),
          end: _at(4),
        );
        expect(result.missing, isEmpty);
        expect(result.hits, hasLength(1));
      });
    });

    group('per-symbol retention window', () {
      test('drops oldest range when total span exceeds retention', () {
        final HistoricalTickCache cache = HistoricalTickCache(
          retentionPerSymbol: const Duration(hours: 4),
        );
        // 2h block at hours [0, 2)
        cache.store(
          symbol: 'BTC',
          ticks: <Tick>[_tick(1)],
          rangeStart: _at(0),
          rangeEnd: _at(2),
        );
        // 2h block at hours [4, 6) — total span = 4h, still fits
        cache.store(
          symbol: 'BTC',
          ticks: <Tick>[_tick(5)],
          rangeStart: _at(4),
          rangeEnd: _at(6),
        );
        // 2h block at hours [8, 10) — total span = 6h, oldest dropped
        cache.store(
          symbol: 'BTC',
          ticks: <Tick>[_tick(9)],
          rangeStart: _at(8),
          rangeEnd: _at(10),
        );

        // After eviction, covered ranges are [4,6) and [8,10).
        // Querying the full [0,10) interval should now report:
        //   * hits at hours 5 and 9 (tick at hour 1 was evicted),
        //   * two missing sub-ranges: [0,4) (before first) and
        //     [6,8) (between).
        final CacheLookup result = cache.lookup(
          symbol: 'BTC',
          start: _at(0),
          end: _at(10),
        );
        expect(
          result.hits.map((Tick t) => t.timestamp.hour),
          <int>[5, 9],
          reason: 'tick at hour 1 should have been evicted with the old range',
        );
        expect(result.missing, hasLength(2));
        expect(result.missing[0].start, _at(0));
        expect(result.missing[0].end, _at(4));
        expect(result.missing[1].start, _at(6));
        expect(result.missing[1].end, _at(8));
      });
    });

    group('LRU symbol eviction', () {
      test('evicts the least-recently-used symbol when over the limit', () {
        final HistoricalTickCache cache = HistoricalTickCache(
          maxSymbols: 2,
        );
        cache.store(
          symbol: 'BTC',
          ticks: <Tick>[_tick(1)],
          rangeStart: _at(0),
          rangeEnd: _at(2),
        );
        cache.store(
          symbol: 'ETH',
          ticks: <Tick>[_tick(1)],
          rangeStart: _at(0),
          rangeEnd: _at(2),
        );
        // Touch BTC so it's the MRU; ETH is now the LRU.
        cache.lookup(symbol: 'BTC', start: _at(0), end: _at(2));

        cache.store(
          symbol: 'SOL',
          ticks: <Tick>[_tick(1)],
          rangeStart: _at(0),
          rangeEnd: _at(2),
        );

        expect(cache.symbolCount, 2);
        // ETH was LRU, should be gone.
        expect(
          cache.lookup(symbol: 'ETH', start: _at(0), end: _at(2)).hits,
          isEmpty,
        );
        // BTC + SOL are warm.
        expect(
          cache.lookup(symbol: 'BTC', start: _at(0), end: _at(2)).hits,
          isNotEmpty,
        );
        expect(
          cache.lookup(symbol: 'SOL', start: _at(0), end: _at(2)).hits,
          isNotEmpty,
        );
      });
    });

    group('clear', () {
      test('drops every cached symbol', () {
        final HistoricalTickCache cache = HistoricalTickCache();
        cache.store(
          symbol: 'BTC',
          ticks: <Tick>[_tick(1)],
          rangeStart: _at(0),
          rangeEnd: _at(2),
        );
        expect(cache.symbolCount, 1);
        cache.clear();
        expect(cache.symbolCount, 0);
        expect(cache.tickCount, 0);
      });
    });

    group('sorted-merge invariants', () {
      // The cache replaced its addAll+sort with an O(n+m) two-way
      // merge over pre-sorted runs (see _SymbolCache._mergeSorted).
      // These tests pin the invariants the chart relies on:
      //   - relative ordering preserved after every store;
      //   - existing entries never dropped (regression for the
      //     `..clear()..addAll(_mergeSorted(_ticks, ...))` cascade
      //     bug, where _mergeSorted ran AFTER clear and silently
      //     consumed an empty list);
      //   - interleaved timestamps interleave correctly.
      test(
        'preserves chronological order across multiple stores',
        () {
          final HistoricalTickCache cache = HistoricalTickCache();
          cache.store(
            symbol: 'BTC',
            ticks: <Tick>[_tick(2), _tick(4)],
            rangeStart: _at(0),
            rangeEnd: _at(5),
          );
          cache.store(
            symbol: 'BTC',
            ticks: <Tick>[_tick(6), _tick(8)],
            rangeStart: _at(5),
            rangeEnd: _at(9),
          );
          final List<int> hours = cache
              .lookup(symbol: 'BTC', start: _at(0), end: _at(10))
              .hits
              .map((Tick t) => t.timestamp.hour)
              .toList();
          expect(hours, <int>[2, 4, 6, 8]);
        },
      );

      test(
        'second store with earlier ticks interleaves rather than '
        'appending',
        () {
          final HistoricalTickCache cache = HistoricalTickCache();
          // Store the LATER range first.
          cache.store(
            symbol: 'BTC',
            ticks: <Tick>[_tick(6), _tick(8)],
            rangeStart: _at(5),
            rangeEnd: _at(9),
          );
          // Then prepend an EARLIER range. The merge must interleave
          // rather than just append, otherwise the chart would emit
          // out-of-order candles on history extension.
          cache.store(
            symbol: 'BTC',
            ticks: <Tick>[_tick(2), _tick(4)],
            rangeStart: _at(0),
            rangeEnd: _at(5),
          );
          final List<int> hours = cache
              .lookup(symbol: 'BTC', start: _at(0), end: _at(10))
              .hits
              .map((Tick t) => t.timestamp.hour)
              .toList();
          expect(hours, <int>[2, 4, 6, 8]);
        },
      );

      test(
        'never drops existing entries when the second store '
        'introduces overlapping timestamps',
        () {
          final HistoricalTickCache cache = HistoricalTickCache();
          cache.store(
            symbol: 'BTC',
            ticks: <Tick>[_tick(2), _tick(4), _tick(6)],
            rangeStart: _at(0),
            rangeEnd: _at(7),
          );
          cache.store(
            symbol: 'BTC',
            ticks: <Tick>[_tick(3), _tick(5)],
            rangeStart: _at(0),
            rangeEnd: _at(7),
          );
          final List<int> hours = cache
              .lookup(symbol: 'BTC', start: _at(0), end: _at(10))
              .hits
              .map((Tick t) => t.timestamp.hour)
              .toList();
          expect(hours, <int>[2, 3, 4, 5, 6]);
        },
      );
    });
  });
}
