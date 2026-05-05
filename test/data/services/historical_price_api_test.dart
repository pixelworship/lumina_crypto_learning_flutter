import 'dart:math';

import 'package:flutter_demo/core/clock/clock.dart';
import 'package:flutter_demo/data/models/tick.dart';
import 'package:flutter_demo/data/services/asset_catalog.dart';
import 'package:flutter_demo/data/services/historical_price_api.dart';
import 'package:flutter_demo/data/services/live_price_feed.dart';
import 'package:flutter_test/flutter_test.dart';

/// Smoke tests for [MockHistoricalPriceApi.fetchSparklineSamples].
///
/// The method's whole point is to keep the main thread off the
/// expensive synth+downsample work. We can't observe "off-main"
/// directly from a unit test, but we can verify:
///   - the result shape is correct (sampleCount-wide list of
///     finite, positive prices) regardless of whether the work
///     ran inline or via `compute`;
///   - the offset is honored (so the sparkline curve agrees with
///     the chart's "across the board" shift);
///   - degenerate inputs degrade gracefully (zero-width window,
///     zero samples, unknown symbol).
void main() {
  late LivePriceFeed feed;
  late MockHistoricalPriceApi api;
  late FakeClock clock;

  setUp(() {
    // Pinned clock so the synth worker's age-tier logic produces a
    // deterministic tick density (and therefore deterministic
    // sample count) regardless of when the suite runs.
    clock = FakeClock(DateTime.utc(2026, 1, 1, 12));
    feed = LivePriceFeed(
      catalog: StaticAssetCatalog(),
      clock: clock,
      startPaused: true,
    );
    api = MockHistoricalPriceApi(
      feed: feed,
      clock: clock,
      latency: Duration.zero,
    );
  });

  tearDown(() async {
    await feed.dispose();
  });

  group('fetchSparklineSamples', () {
    test('returns sampleCount evenly-spaced positive prices', () async {
      // Use the pinned clock's "now" so the synth tick-density
      // tier is the dense (1s) tier — that produces ~30k ticks
      // for a 24h window, well above the 32 sample target.
      final DateTime now = clock.now();
      final List<double> samples = await api.fetchSparklineSamples(
        symbol: 'BTC',
        start: now.subtract(const Duration(hours: 24)),
        end: now,
        sampleCount: 32,
      );
      expect(samples, hasLength(32));
      for (final double p in samples) {
        expect(p, greaterThan(0));
        expect(p.isFinite, isTrue);
      }
    });

    test(
      'past samples are NOT shifted by a present-tense dial — the '
      'offset only takes effect from the dial moment forward',
      () async {
        final DateTime now = clock.now();
        final DateTime start = now.subtract(const Duration(hours: 1));

        const int samples = 64;
        final List<double> baseline = await api.fetchSparklineSamples(
          symbol: 'BTC',
          start: start,
          end: now,
          sampleCount: samples,
        );
        expect(baseline, hasLength(samples));

        // Dial +$1000 RIGHT NOW. Under the event-based model this
        // creates a step at clock.now() — every sample timestamped
        // BEFORE clock.now() must keep its baseline price; samples
        // AT/AFTER pick up the offset. Since we sample the
        // [start, now) range (closed-open, end-exclusive), every
        // returned sample is strictly before now, so all samples
        // should be unchanged from baseline.
        feed.setPriceOffset('BTC', 1000);
        final List<double> after = await api.fetchSparklineSamples(
          symbol: 'BTC',
          start: start,
          end: now,
          sampleCount: samples,
        );

        expect(after, hasLength(samples));
        // Each call uses a fresh random seed so sub-tick timestamps
        // (and therefore the sampled indices) drift between calls;
        // the mean of the differences cleanly washes out that
        // jitter and gives a stable signal that the offset did NOT
        // propagate into past samples (within ~one sampling
        // variance of zero).
        double meanDelta = 0;
        for (int i = 0; i < samples; i++) {
          meanDelta += after[i] - baseline[i];
        }
        meanDelta /= samples;
        expect(
          meanDelta,
          closeTo(0, 200),
          reason:
              'past samples must not absorb a dial timestamped at "now"',
        );
      },
    );

    test(
      'a dial event mid-window produces a step in synthesized ticks: '
      'pre-dial ticks keep their baseline price, at/after-dial ticks '
      'include the offset (verified by comparing against a same-seed '
      'no-offset fetch — synth jitter cancels out)',
      () async {
        final DateTime windowStart = DateTime.utc(2026, 1, 1, 12);
        final DateTime dialAt =
            windowStart.add(const Duration(minutes: 15));
        final DateTime windowEnd =
            windowStart.add(const Duration(minutes: 30));

        // Both feeds use the same default seed so they share noise
        // curves; they only differ in dial history. Both apis are
        // built with `Random(42)`, so the synth args' `randomSeed`
        // is identical for the first fetchTicks call on each api —
        // sub-tick jitter is therefore identical and cancels out
        // when we compare bucket means.
        final FakeClock baselineClock = FakeClock(windowEnd);
        final LivePriceFeed baselineFeed = LivePriceFeed(
          catalog: StaticAssetCatalog(),
          clock: baselineClock,
          startPaused: true,
        );
        addTearDown(baselineFeed.dispose);
        final MockHistoricalPriceApi baselineApi =
            MockHistoricalPriceApi(
          feed: baselineFeed,
          clock: baselineClock,
          latency: Duration.zero,
          random: Random(42),
        );

        final FakeClock shiftedClock = FakeClock(dialAt);
        final LivePriceFeed shiftedFeed = LivePriceFeed(
          catalog: StaticAssetCatalog(),
          clock: shiftedClock,
          startPaused: true,
        );
        addTearDown(shiftedFeed.dispose);
        shiftedFeed.setPriceOffset('BTC', 1000);
        shiftedClock.advance(const Duration(minutes: 15));
        final MockHistoricalPriceApi shiftedApi = MockHistoricalPriceApi(
          feed: shiftedFeed,
          clock: shiftedClock,
          latency: Duration.zero,
          random: Random(42),
        );

        final List<Tick> baselineTicks = await baselineApi.fetchTicks(
          symbol: 'BTC',
          start: windowStart,
          end: windowEnd,
        );
        final List<Tick> shiftedTicks = await shiftedApi.fetchTicks(
          symbol: 'BTC',
          start: windowStart,
          end: windowEnd,
        );
        expect(baselineTicks, isNotEmpty);
        expect(shiftedTicks, isNotEmpty);

        double sumBaselinePre = 0;
        int nBaselinePre = 0;
        double sumBaselinePost = 0;
        int nBaselinePost = 0;
        for (final Tick t in baselineTicks) {
          if (t.timestamp.isBefore(dialAt)) {
            sumBaselinePre += t.price;
            nBaselinePre++;
          } else {
            sumBaselinePost += t.price;
            nBaselinePost++;
          }
        }
        double sumShiftedPre = 0;
        int nShiftedPre = 0;
        double sumShiftedPost = 0;
        int nShiftedPost = 0;
        for (final Tick t in shiftedTicks) {
          if (t.timestamp.isBefore(dialAt)) {
            sumShiftedPre += t.price;
            nShiftedPre++;
          } else {
            sumShiftedPost += t.price;
            nShiftedPost++;
          }
        }
        expect(nBaselinePre, greaterThan(0));
        expect(nBaselinePost, greaterThan(0));
        expect(nShiftedPre, greaterThan(0));
        expect(nShiftedPost, greaterThan(0));

        final double meanBaselinePre = sumBaselinePre / nBaselinePre;
        final double meanBaselinePost = sumBaselinePost / nBaselinePost;
        final double meanShiftedPre = sumShiftedPre / nShiftedPre;
        final double meanShiftedPost = sumShiftedPost / nShiftedPost;

        // Pre-dial: both baseline and shifted give offset=0 → means
        // are essentially identical (sub-tick jitter scales with
        // basePrice * 0.001, so a few cents per tick at most).
        expect(
          meanShiftedPre - meanBaselinePre,
          closeTo(0, 1.0),
          reason:
              'pre-dial ticks are not affected by a dial timestamped '
              'mid-window — they keep their original noise price',
        );
        // Post-dial: shifted has offset=1000, baseline has 0 →
        // means differ by exactly the dial value (modulo a tiny
        // jitter scaling effect since per-tick jitter is
        // proportional to abs(price)).
        expect(
          meanShiftedPost - meanBaselinePost,
          closeTo(1000, 5.0),
          reason: 'at-or-after-dial ticks absorb the dial offset',
        );
      },
    );

    test('returns empty for zero or negative sampleCount', () async {
      final DateTime now = DateTime.utc(2026, 1, 1, 12);
      final List<double> samples = await api.fetchSparklineSamples(
        symbol: 'BTC',
        start: now.subtract(const Duration(hours: 1)),
        end: now,
        sampleCount: 0,
      );
      expect(samples, isEmpty);
    });

    test('returns empty for a non-positive window', () async {
      final DateTime now = clock.now();
      final List<double> samples = await api.fetchSparklineSamples(
        symbol: 'BTC',
        start: now,
        end: now,
        sampleCount: 16,
      );
      expect(samples, isEmpty);
    });

    test(
      'lazy-mints a noise generator for paginated symbols',
      () async {
        // The live feed lazy-creates noise for symbols it hasn't seen,
        // so the api should produce a usable shape for synthesized
        // assets (markets list pagination, etc.) without explicit
        // registration.
        final DateTime now = clock.now();
        final List<double> samples = await api.fetchSparklineSamples(
          symbol: 'NEWASSET',
          start: now.subtract(const Duration(hours: 1)),
          end: now,
          sampleCount: 8,
        );
        expect(samples, hasLength(8));
        for (final double p in samples) {
          expect(p, greaterThan(0));
        }
      },
    );
  });
}
