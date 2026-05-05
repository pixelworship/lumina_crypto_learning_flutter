import 'package:flutter_demo/core/clock/clock.dart';
import 'package:flutter_demo/data/services/asset_catalog.dart';
import 'package:flutter_demo/data/services/live_price_feed.dart';
import 'package:flutter_test/flutter_test.dart';

/// Targeted tests for the debug price-offset feature.
///
/// The feature is modeled as a step function over time, NOT a single
/// mutable value: each [LivePriceFeed.setPriceOffset] call appends a
/// dial event at the current wall clock. Prices BEFORE the event
/// keep whatever offset was in force at their original time
/// (typically zero — the past was the past); prices FROM the event
/// onward use the new dial value. Visually this renders as a clean
/// step at the moment of the press across the chart, the markets
/// row, the portfolio, and the trade card — like a real-world
/// volume-driven spike, instead of the entire historical curve
/// uniformly sliding up/down with the dial.
void main() {
  late FakeClock clock;
  late LivePriceFeed feed;

  setUp(() {
    clock = FakeClock(DateTime.utc(2026, 1, 1, 12));
    feed = LivePriceFeed(
      catalog: StaticAssetCatalog(),
      clock: clock,
      // Pause the periodic timer so tests are entirely driven by
      // explicit `setPriceOffset`-triggered broadcasts.
      startPaused: true,
    );
  });

  tearDown(() async {
    await feed.dispose();
  });

  group('LivePriceFeed.priceAt event-based offset semantics', () {
    test(
      'past prices are NOT retroactively shifted by a dial happening now',
      () {
        // Dial events take effect AT their timestamp; a press just
        // now must not retroactively shift yesterday's price.
        final DateTime past = clock.now().subtract(const Duration(hours: 24));
        final double baseline = feed.priceAt('BTC', past);

        feed.setPriceOffset('BTC', 1000);

        expect(feed.priceAt('BTC', past), closeTo(baseline, 0.01));
      },
    );

    test(
      'priceAt at the dial timestamp DOES include the new offset '
      '(the lookup is `<= t`, so the event applies the moment it lands)',
      () {
        final DateTime now = clock.now();
        final double baseline = feed.priceAt('BTC', now);

        feed.setPriceOffset('BTC', 750);

        expect(feed.priceAt('BTC', now), closeTo(baseline + 750, 0.01));
      },
    );

    test(
      'priceAt for a time AFTER the dial event includes the new offset',
      () {
        final DateTime future = clock.now().add(const Duration(hours: 6));
        final double baseline = feed.priceAt('BTC', future);

        feed.setPriceOffset('BTC', 500);

        expect(feed.priceAt('BTC', future), closeTo(baseline + 500, 0.01));
      },
    );

    test('only shifts the symbol that was dialed', () {
      final DateTime now = clock.now();
      final double btcBefore = feed.priceAt('BTC', now);
      final double ethBefore = feed.priceAt('ETH', now);

      feed.setPriceOffset('BTC', 250);

      expect(feed.priceAt('BTC', now), closeTo(btcBefore + 250, 0.01));
      expect(feed.priceAt('ETH', now), closeTo(ethBefore, 0.01));
    });

    test(
      'dialing back to 0 drops the live price back to the noise curve '
      'at the moment of the clear (without erasing history)',
      () {
        final double baseline = feed.currentPrice('BTC');

        feed.setPriceOffset('BTC', 500);
        expect(feed.currentPrice('BTC'), closeTo(baseline + 500, 0.01));

        feed.setPriceOffset('BTC', 0);
        expect(feed.currentPrice('BTC'), closeTo(baseline, 0.01));
      },
    );

    test(
      'multiple sequential dials produce a step sequence — past windows '
      'reflect the offset that was active during that window, not the '
      'latest dial',
      () {
        // Wind the clock forward in two stages, dialing in between
        // each stage. After both dials, the price for a timestamp
        // INSIDE the window between the two dials should reflect the
        // first dial's offset (50), not the second's (200) — even
        // though the second dial is the one currently in force.
        final DateTime t0 = clock.now();
        feed.setPriceOffset('BTC', 50);
        clock.advance(const Duration(hours: 1));
        final DateTime betweenDials = clock.now();
        clock.advance(const Duration(hours: 1));
        feed.setPriceOffset('BTC', 200);

        // Sample the price at `betweenDials` — should pick up offset
        // 50 (the dial that was in force during that window), NOT
        // the latest dial of 200 and NOT the original 0.
        // Compute the expected value using a fresh feed with no
        // dials so we can isolate the noise contribution.
        final FakeClock probeClock = FakeClock(t0);
        final LivePriceFeed probe = LivePriceFeed(
          catalog: StaticAssetCatalog(),
          clock: probeClock,
          startPaused: true,
        );
        final double noiseAtBetween = probe.priceAt('BTC', betweenDials);
        probe.dispose();

        expect(
          feed.priceAt('BTC', betweenDials),
          closeTo(noiseAtBetween + 50, 0.01),
        );
      },
    );
  });

  group('LivePriceUpdate.offsets', () {
    test(
      'broadcasts an empty offsets map before any debug dial',
      () async {
        final Future<LivePriceUpdate> next = feed.watchAll().first;
        // Trigger an emission via setPriceOffset(symbol, 0) — a no-op
        // dial that still flushes a fresh broadcast.
        feed.setPriceOffset('BTC', 0);
        final LivePriceUpdate update = await next;
        // We may have other symbols in the offsets map at value 0,
        // but no symbol should be non-zero at this point.
        for (final double v in update.offsets.values) {
          expect(v, 0);
        }
      },
    );

    test('broadcasts the dialed offset on the next emission', () async {
      final Future<LivePriceUpdate> next = feed.watchAll().first;
      feed.setPriceOffset('BTC', 750);
      final LivePriceUpdate update = await next;
      expect(update.offsets['BTC'], 750);
    });

    test('broadcasts independent offsets per symbol', () async {
      feed.setPriceOffset('BTC', 100);
      // Capture the broadcast triggered by the second dial (the second
      // setPriceOffset call also triggers an emit).
      final Future<LivePriceUpdate> next = feed.watchAll().first;
      feed.setPriceOffset('ETH', -50);
      final LivePriceUpdate update = await next;
      expect(update.offsets['BTC'], 100);
      expect(update.offsets['ETH'], -50);
    });

    test('reflects the latest dial when the offset is updated', () async {
      feed.setPriceOffset('BTC', 100);
      final Future<LivePriceUpdate> next = feed.watchAll().first;
      feed.setPriceOffset('BTC', 250);
      final LivePriceUpdate update = await next;
      expect(update.offsets['BTC'], 250);
    });

    test('embeds shifted prices alongside shifted offsets', () async {
      final double baselineBtc = feed.currentPrice('BTC');
      final Future<LivePriceUpdate> next = feed.watchAll().first;
      feed.setPriceOffset('BTC', 500);
      final LivePriceUpdate update = await next;
      // Both the price map and the offsets map agree the dial was
      // applied — anything else would mean the bloc layer can't
      // trust the broadcast for "across the board" shifting.
      expect(update.offsets['BTC'], 500);
      expect(update.prices['BTC'], closeTo(baselineBtc + 500, 0.01));
    });
  });

  group('LivePriceFeed.priceOffset', () {
    test('returns 0 for an unset symbol', () {
      expect(feed.priceOffset('BTC'), 0);
    });

    test('returns the most recently dialed offset', () {
      feed.setPriceOffset('BTC', 200);
      expect(feed.priceOffset('BTC'), 200);
      feed.setPriceOffset('BTC', -75);
      expect(feed.priceOffset('BTC'), -75);
    });

    test('lookup is case insensitive', () {
      feed.setPriceOffset('btc', 50);
      expect(feed.priceOffset('BTC'), 50);
      expect(feed.priceOffset('bTc'), 50);
    });
  });

  group('LivePriceFeed.offsetEvents', () {
    test('returns an empty list for symbols with no dial history', () {
      expect(feed.offsetEvents('BTC'), isEmpty);
    });

    test(
      'records every dial as an event, in order, with the wall clock '
      'timestamp of the call',
      () {
        feed.setPriceOffset('BTC', 100);
        clock.advance(const Duration(seconds: 30));
        final DateTime t1 = clock.now();
        feed.setPriceOffset('BTC', 250);
        clock.advance(const Duration(minutes: 5));
        final DateTime t2 = clock.now();
        feed.setPriceOffset('BTC', 0);

        final List<OffsetEvent> events = feed.offsetEvents('BTC');
        expect(events, hasLength(3));
        // First event is at the original clock.now() — captured
        // before we advanced. We don't pin its exact timestamp here
        // (it's whatever setUp's clock was set to); we just check
        // ordering and offsets.
        expect(events[0].offset, 100);
        expect(events[1].offset, 250);
        expect(events[1].timestamp, t1);
        expect(events[2].offset, 0);
        expect(events[2].timestamp, t2);
      },
    );

    test('returned list is unmodifiable', () {
      feed.setPriceOffset('BTC', 100);
      final List<OffsetEvent> events = feed.offsetEvents('BTC');
      expect(
        () => events.add((timestamp: clock.now(), offset: 999)),
        throwsUnsupportedError,
      );
    });
  });
}
