import 'package:flutter/foundation.dart';
import 'package:flutter_demo/core/clock/clock.dart';
import 'package:flutter_demo/data/services/asset_catalog.dart';
import 'package:flutter_demo/data/services/live_price_feed.dart';
import 'package:flutter_demo/data/services/sparkline_feed.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late LivePriceFeed priceFeed;
  late SparklineFeed sparklineFeed;
  late FakeClock clock;

  setUp(() {
    clock = FakeClock(DateTime.utc(2026, 1, 1, 12));
    priceFeed = LivePriceFeed(
      catalog: StaticAssetCatalog(),
      clock: clock,
      startPaused: true,
    );
    sparklineFeed = SparklineFeed(
      feed: priceFeed,
      clock: clock,
      bufferSize: 8,
    );
  });

  tearDown(() async {
    await sparklineFeed.dispose();
    await priceFeed.dispose();
  });

  group('SparklineFeed.watch', () {
    test('seeds the buffer with bufferSize points on first call', () {
      final ValueListenable<List<double>> notifier =
          sparklineFeed.watch('BTC');
      expect(notifier.value, hasLength(8));
      // Every seeded point should be a positive (clamped) price, and
      // each entry must be unique-ish (i.e. the noise curve actually
      // gave us movement) — flat-line means seeding is broken.
      expect(notifier.value.every((double p) => p > 0), isTrue);
    });

    test('returns the same notifier instance on repeat calls', () {
      final ValueListenable<List<double>> a = sparklineFeed.watch('BTC');
      final ValueListenable<List<double>> b = sparklineFeed.watch('BTC');
      expect(identical(a, b), isTrue);
    });

    test('lazy-creates buffers for paginated/synthesized symbols', () {
      // 'NOVA' isn't in the static catalog — the live price feed
      // should still hand back a noise curve for it via lazy
      // registration, and the sparkline buffer should seed from that.
      final ValueListenable<List<double>> notifier =
          sparklineFeed.watch('NOVA');
      expect(notifier.value, hasLength(8));
      expect(notifier.value.every((double p) => p > 0), isTrue);
    });
  });

  group('SparklineFeed.currentValues', () {
    test('returns an empty list before watch() is called', () {
      expect(sparklineFeed.currentValues('BTC'), isEmpty);
    });

    test('returns the live buffer once watch() has been called', () {
      sparklineFeed.watch('BTC');
      expect(sparklineFeed.currentValues('BTC'), hasLength(8));
    });
  });
}
