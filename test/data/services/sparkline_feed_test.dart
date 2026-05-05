import 'package:flutter/foundation.dart';
import 'package:flutter_demo/core/clock/clock.dart';
import 'package:flutter_demo/data/models/tick.dart';
import 'package:flutter_demo/data/services/asset_catalog.dart';
import 'package:flutter_demo/data/services/historical_price_api.dart';
import 'package:flutter_demo/data/services/live_price_feed.dart';
import 'package:flutter_demo/data/services/sparkline_feed.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stand-in warehouse api: returns a deterministic ramp of [tickCount]
/// prices spread evenly across the requested window.
///
/// Configurable behavior:
/// - [latency]: simulated network delay (defaults to zero so tests
///   resolve in the same microtask).
/// - [failOnFetch]: throws an `Exception` instead of returning ticks
///   so we can exercise the feed's warehouse-failure path.
class _FakeHistoricalPriceApi implements HistoricalPriceApi {
  _FakeHistoricalPriceApi({
    this.latency = Duration.zero,
    this.failOnFetch = false,
    this.tickCount = 64,
  });

  final Duration latency;
  final bool failOnFetch;
  final int tickCount;

  /// Symbols this fake was asked about — useful for asserting the
  /// feed actually round-trips through the warehouse api.
  final List<String> queriedSymbols = <String>[];

  @override
  Future<List<Tick>> fetchTicks({
    required String symbol,
    required DateTime start,
    required DateTime end,
  }) async {
    queriedSymbols.add(symbol);
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (failOnFetch) throw Exception('warehouse down');
    final int spanMs = end.difference(start).inMilliseconds;
    return <Tick>[
      for (int i = 0; i < tickCount; i++)
        Tick(
          // Linear ramp keeps the assertion cheap (max - min == tickCount-1)
          // and lets us read off the down-sample picks.
          price: 100.0 + i,
          side: TickSide.buy,
          volume: 1.0,
          timestamp: start.add(
            Duration(
              milliseconds: tickCount > 1
                  ? (spanMs * i / (tickCount - 1)).round()
                  : 0,
            ),
          ),
        ),
    ];
  }

  /// Mirrors [fetchTicks] but downsamples to [sampleCount] in the
  /// fake — letting the sparkline feed test the
  /// `fetchSparklineSamples` path end to end without a real isolate.
  @override
  Future<List<double>> fetchSparklineSamples({
    required String symbol,
    required DateTime start,
    required DateTime end,
    required int sampleCount,
  }) async {
    final List<Tick> ticks =
        await fetchTicks(symbol: symbol, start: start, end: end);
    if (ticks.isEmpty || sampleCount <= 0) return const <double>[];
    if (ticks.length <= sampleCount) {
      return <double>[for (final Tick t in ticks) t.price];
    }
    final List<double> result = List<double>.filled(sampleCount, 0.0);
    final double scale = (ticks.length - 1) / (sampleCount - 1);
    for (int i = 0; i < sampleCount; i++) {
      final int idx = (i * scale).round();
      result[i] = ticks[idx].price;
    }
    return result;
  }
}

void main() {
  late LivePriceFeed priceFeed;
  late _FakeHistoricalPriceApi historicalApi;
  late FakeClock clock;

  setUp(() {
    clock = FakeClock(DateTime.utc(2026, 1, 1, 12));
    priceFeed = LivePriceFeed(
      catalog: StaticAssetCatalog(),
      clock: clock,
      startPaused: true,
    );
    historicalApi = _FakeHistoricalPriceApi();
  });

  tearDown(() async {
    await priceFeed.dispose();
  });

  SparklineFeed buildFeed({
    _FakeHistoricalPriceApi? api,
    int bufferSize = 8,
  }) {
    return SparklineFeed(
      feed: priceFeed,
      historicalApi: api ?? historicalApi,
      clock: clock,
      bufferSize: bufferSize,
    );
  }

  group('SparklineFeed.watch', () {
    test('starts in loading state with no values', () {
      final SparklineFeed sparklineFeed = buildFeed();
      addTearDown(sparklineFeed.dispose);

      final ValueListenable<SparklineSnapshot> notifier =
          sparklineFeed.watch('BTC');

      expect(notifier.value.isLoading, isTrue);
      expect(notifier.value.values, isEmpty);
    });

    test(
      'hydrates from the warehouse api and clears the loading flag',
      () async {
        final SparklineFeed sparklineFeed = buildFeed();
        addTearDown(sparklineFeed.dispose);

        final ValueListenable<SparklineSnapshot> notifier =
            sparklineFeed.watch('BTC');

        // The fake api resolves on the next microtask — yield once so
        // the feed's seed future runs to completion before we inspect.
        await Future<void>.delayed(Duration.zero);

        expect(notifier.value.isLoading, isFalse);
        expect(notifier.value.values, hasLength(8));
        expect(notifier.value.values.every((double p) => p > 0), isTrue);
        expect(historicalApi.queriedSymbols, contains('BTC'));
      },
    );

    test('returns the same notifier instance on repeat calls', () {
      final SparklineFeed sparklineFeed = buildFeed();
      addTearDown(sparklineFeed.dispose);

      final ValueListenable<SparklineSnapshot> a = sparklineFeed.watch('BTC');
      final ValueListenable<SparklineSnapshot> b = sparklineFeed.watch('BTC');

      expect(identical(a, b), isTrue);
    });

    test(
      'down-samples a wide tick stream evenly across bufferSize slots',
      () async {
        // 64 ticks -> 8 slots, evenly spaced — the down-sampler should
        // pick (idx 0, 9, 18, ...) so the first sample is the start
        // and the last sample is the end of the ramp.
        final SparklineFeed sparklineFeed = buildFeed(
          api: _FakeHistoricalPriceApi(tickCount: 64),
          bufferSize: 8,
        );
        addTearDown(sparklineFeed.dispose);

        final ValueListenable<SparklineSnapshot> notifier =
            sparklineFeed.watch('BTC');
        await Future<void>.delayed(Duration.zero);

        expect(notifier.value.isLoading, isFalse);
        expect(notifier.value.values, hasLength(8));
        // First slot pegged to the very first tick (price = 100.0),
        // last slot pegged to the very last tick (price = 100 + 63).
        expect(notifier.value.values.first, 100.0);
        expect(notifier.value.values.last, 163.0);
      },
    );

    test(
      'flips out of loading state even when the warehouse api fails',
      () async {
        final SparklineFeed sparklineFeed = buildFeed(
          api: _FakeHistoricalPriceApi(failOnFetch: true),
        );
        addTearDown(sparklineFeed.dispose);

        final ValueListenable<SparklineSnapshot> notifier =
            sparklineFeed.watch('BTC');

        await Future<void>.delayed(Duration.zero);

        expect(notifier.value.isLoading, isFalse);
        expect(notifier.value.values, isEmpty);
      },
    );

    test('lazy-creates buffers for paginated/synthesized symbols', () async {
      // 'NOVA' isn't in the static catalog — the live feed lazy
      // registers it and the warehouse api still answers (our fake
      // doesn't care about catalog membership), so the sparkline
      // buffer should hydrate from that response.
      final SparklineFeed sparklineFeed = buildFeed();
      addTearDown(sparklineFeed.dispose);

      final ValueListenable<SparklineSnapshot> notifier =
          sparklineFeed.watch('NOVA');
      await Future<void>.delayed(Duration.zero);

      expect(notifier.value.isLoading, isFalse);
      expect(notifier.value.values, hasLength(8));
      expect(historicalApi.queriedSymbols, contains('NOVA'));
    });
  });

  group('SparklineFeed offset propagation', () {
    test(
      'historical seed points stay put across a debug dial — only the '
      'rightmost (live) point absorbs the spike',
      () async {
        // Hydrate the buffer from the warehouse api first so we have
        // concrete points to compare against.
        final SparklineFeed sparklineFeed = buildFeed(
          api: _FakeHistoricalPriceApi(tickCount: 32),
          bufferSize: 8,
        );
        addTearDown(sparklineFeed.dispose);

        final ValueListenable<SparklineSnapshot> notifier =
            sparklineFeed.watch('BTC');
        await Future<void>.delayed(Duration.zero);
        final List<double> baseline =
            List<double>.from(notifier.value.values);
        expect(baseline, hasLength(8));

        // Dial +$500 on the live feed. Under the event-based model
        // this represents a "pump right now" event: yesterday's
        // prices stay where they were, only the live tick at the
        // moment of the press jumps to noise+500. The sparkline
        // buffer reflects this — historical seed points
        // (indices 0..n-2) hold steady; the rightmost slot will
        // move to whatever the new live price is.
        priceFeed.setPriceOffset('BTC', 500);
        await Future<void>.delayed(Duration.zero);

        final List<double> after = notifier.value.values;
        expect(after, hasLength(8));
        for (int i = 0; i < 7; i++) {
          expect(
            after[i],
            closeTo(baseline[i], 0.01),
            reason:
                'historical seed point $i must NOT shift on a present-tense dial',
          );
        }
      },
    );

    test(
      'a buffer is not affected by an unrelated symbol\'s offset dial',
      () async {
        final SparklineFeed sparklineFeed = buildFeed();
        addTearDown(sparklineFeed.dispose);

        sparklineFeed.watch('BTC');
        await Future<void>.delayed(Duration.zero);
        final List<double> btcBefore =
            List<double>.from(sparklineFeed.currentValues('BTC'));

        // Dial ETH while BTC is the only buffered symbol — BTC's
        // historical seed must hold steady.
        priceFeed.setPriceOffset('ETH', 300);
        await Future<void>.delayed(Duration.zero);

        final List<double> btcAfter = sparklineFeed.currentValues('BTC');
        for (int i = 0; i < btcBefore.length - 1; i++) {
          expect(
            btcAfter[i],
            closeTo(btcBefore[i], 0.01),
            reason: 'BTC point $i must not have absorbed an ETH dial',
          );
        }
      },
    );
  });

  group('SparklineFeed live-tick semantics', () {
    test(
      'live ticks update only the rightmost point so the 1-day '
      'historical seed survives many ticks',
      () async {
        // Hydrate from the warehouse (linear ramp 100..107).
        final SparklineFeed sparklineFeed = buildFeed(
          api: _FakeHistoricalPriceApi(tickCount: 8),
          bufferSize: 8,
        );
        addTearDown(sparklineFeed.dispose);

        final ValueListenable<SparklineSnapshot> notifier =
            sparklineFeed.watch('BTC');
        await Future<void>.delayed(Duration.zero);
        final List<double> seed = List<double>.from(notifier.value.values);
        expect(seed, hasLength(8));

        // Drive many synthetic live ticks — far more than bufferSize.
        // `setPriceOffset` calls `_emitNow` every time (even when the
        // value is unchanged), so re-dialing 0 is a clean way to fan
        // a live tick into the sparkline feed without compounding any
        // offset deltas. Under the previous "push + trim head"
        // semantics the buffer would be entirely overwritten with
        // live ticks within `bufferSize` updates, dropping the
        // historical 1-day shape. Replace-last keeps indices
        // `0..n-2` pinned to the seed.
        for (int i = 0; i < 100; i++) {
          priceFeed.setPriceOffset('BTC', 0);
          await Future<void>.delayed(Duration.zero);
        }

        final List<double> values = notifier.value.values;
        expect(values, hasLength(8));
        for (int i = 0; i < 7; i++) {
          expect(
            values[i],
            closeTo(seed[i], 0.01),
            reason:
                'historical seed point $i must survive many live ticks',
          );
        }
      },
    );
  });

  group('SparklineFeed.currentValues', () {
    test('returns an empty list before watch() is called', () {
      final SparklineFeed sparklineFeed = buildFeed();
      addTearDown(sparklineFeed.dispose);

      expect(sparklineFeed.currentValues('BTC'), isEmpty);
    });

    test(
      'returns an empty list while the warehouse fetch is in flight',
      () {
        // Latency > 0 holds the api fetch open across a synchronous
        // inspection, so we can sample mid-load.
        final SparklineFeed sparklineFeed = buildFeed(
          api: _FakeHistoricalPriceApi(
            latency: const Duration(milliseconds: 50),
          ),
        );
        addTearDown(sparklineFeed.dispose);

        sparklineFeed.watch('BTC');
        expect(sparklineFeed.currentValues('BTC'), isEmpty);
        expect(sparklineFeed.isLoading('BTC'), isTrue);
      },
    );

    test('returns the hydrated buffer once the api resolves', () async {
      final SparklineFeed sparklineFeed = buildFeed();
      addTearDown(sparklineFeed.dispose);

      sparklineFeed.watch('BTC');
      await Future<void>.delayed(Duration.zero);

      expect(sparklineFeed.currentValues('BTC'), hasLength(8));
      expect(sparklineFeed.isLoading('BTC'), isFalse);
    });
  });
}
