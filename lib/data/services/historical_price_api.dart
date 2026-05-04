import 'dart:math';

import '../../core/clock/clock.dart';
import '../../core/concurrency/background.dart';
import '../../core/diagnostics/mrm_trace.dart';
import '../models/tick.dart';
import 'live_price_feed.dart';
import 'price_noise.dart';

/// REST-style read API for historical price data.
///
/// Strictly separate from [LivePriceFeed]: that one streams the
/// current price, this one is a stateless query over a closed-open
/// time interval. A real backend would expose this as
/// `GET /history?symbol=BTC&from=...&to=...`.
///
/// Implementations should be **side-effect free** and **idempotent**
/// for a given (symbol, start, end) triple — the cache layer relies
/// on identical inputs producing identical outputs to safely de-dupe
/// repeated requests.
abstract class HistoricalPriceApi {
  Future<List<Tick>> fetchTicks({
    required String symbol,
    required DateTime start,
    required DateTime end,
  });
}

/// Mock historical API. Synthesizes ticks for any time range using
/// the asset's [PriceNoise] from the shared [LivePriceFeed], so live
/// and historical prices share a single curve and the boundary
/// between them is seamless.
///
/// Density is **age-tiered**: dense (~1s) ticks for recent data so
/// short timeframes have OHLC variation, progressively sparser ticks
/// further in the past so a year-long range fits in a reasonable
/// memory budget.
///
/// The actual synthesis loop runs on a background isolate via
/// [runOffMain] so a 24h request (≈30k ticks of `priceAt` work)
/// doesn't block the UI thread while the user is mid-tap.
class MockHistoricalPriceApi implements HistoricalPriceApi {
  MockHistoricalPriceApi({
    required LivePriceFeed feed,
    Clock clock = const SystemClock(),
    Duration latency = const Duration(milliseconds: 250),
    double tickJitter = 0.15,
    Random? random,
  }) : _feed = feed,
       _clock = clock,
       _latency = latency,
       _tickJitter = tickJitter,
       _random = random ?? Random();

  final LivePriceFeed _feed;
  final Clock _clock;
  final Duration _latency;
  final double _tickJitter;
  final Random _random;

  @override
  Future<List<Tick>> fetchTicks({
    required String symbol,
    required DateTime start,
    required DateTime end,
  }) async {
    MrmTrace.mark(60, 'Api.fetchTicks start',
        'symbol=$symbol latency=${_latency.inMilliseconds}ms');
    final PriceNoise? noise = _feed.noiseFor(symbol);
    if (noise == null || !end.isAfter(start)) return const <Tick>[];
    if (_latency > Duration.zero) {
      await Future<void>.delayed(_latency);
    }
    MrmTrace.mark(61, 'Api latency delay done');
    // Capture the offset + clock once per call so every tick in this
    // fetch is consistent — and bakes the offset into synthesized
    // history exactly the same way live ticks bake it into the
    // present.
    final _SynthArgs args = (
      noise: noise,
      startMs: start.millisecondsSinceEpoch,
      endMs: end.millisecondsSinceEpoch,
      nowMs: _clock.now().millisecondsSinceEpoch,
      offset: _feed.priceOffset(symbol),
      tickJitter: _tickJitter,
      randomSeed: _random.nextInt(1 << 32),
    );

    // Ballpark tick count so trivial windows (a few seconds of
    // backfill) skip the isolate hop entirely.
    final int estimatedTicks = _estimateTickCount(start, end, args.nowMs);
    MrmTrace.mark(62, 'Api synth dispatch',
        'estimated=$estimatedTicks isolate=${estimatedTicks >= 2000}');
    final List<Tick> ticks = await runOffMain<_SynthArgs, List<Tick>>(
      _synthesizeTicksWorker,
      args,
      heuristicSize: estimatedTicks,
      debugLabel: 'historical-synth-$symbol',
    );
    MrmTrace.mark(63, 'Api synth done', 'ticks=${ticks.length}');
    return ticks;
  }
}

/// Number of sub-ticks emitted within each anchor interval so
/// aggregated candles always have OHLC variation instead of
/// collapsing to a single flat-line tick.
const int _ticksPerAnchor = 6;

/// Tick interval (ms) as a function of how far in the past `t` is.
/// Recent → seconds. Far past → hours.
int _intervalForAge(Duration age) {
  if (age > const Duration(days: 30)) return 6 * 60 * 60 * 1000; // 6h
  if (age > const Duration(days: 1)) return 30 * 60 * 1000; // 30m
  if (age > const Duration(hours: 1)) return 60 * 1000; // 60s
  return 1000; // 1s
}

int _decimalsFor(double price) {
  if (price >= 100) return 2;
  if (price >= 1) return 4;
  return 6;
}

/// Cheap upper-bound estimate of the tick count a [start]..[end]
/// window will produce, used to decide whether to spawn an isolate.
/// We assume worst-case (everything in the densest age tier).
int _estimateTickCount(DateTime start, DateTime end, int nowMs) {
  final int spanMs = end.millisecondsSinceEpoch - start.millisecondsSinceEpoch;
  if (spanMs <= 0) return 0;
  // Cheapest interval across the window dictates worst-case density.
  // Anything ≤ 1h of recent data is at the 1s tier (1000ms).
  return (spanMs / 1000).ceil() * _ticksPerAnchor;
}

/// Top-level so it can be sent to [compute]. Keep this stateless and
/// pure — no `Random()` defaults, no clock reads — to preserve
/// determinism across isolates.
typedef _SynthArgs = ({
  PriceNoise noise,
  int startMs,
  int endMs,
  int nowMs,
  double offset,
  double tickJitter,
  int randomSeed,
});

List<Tick> _synthesizeTicksWorker(_SynthArgs args) {
  final Random rng = Random(args.randomSeed);
  final DateTime start = DateTime.fromMillisecondsSinceEpoch(args.startMs);
  final DateTime end = DateTime.fromMillisecondsSinceEpoch(args.endMs);
  final DateTime now = DateTime.fromMillisecondsSinceEpoch(args.nowMs);
  final List<Tick> ticks = <Tick>[];
  DateTime t = start;
  while (t.isBefore(end)) {
    final Duration age = now.difference(t);
    final int intervalMs = _intervalForAge(age);
    final double subStepMs = intervalMs / _ticksPerAnchor;
    for (int i = 0; i < _ticksPerAnchor; i++) {
      final int baseOffsetMs = (subStepMs * i).round();
      final int subJitterMs =
          ((rng.nextDouble() - 0.5) * 0.5 * subStepMs).round();
      final DateTime subT =
          t.add(Duration(milliseconds: baseOffsetMs + subJitterMs));
      if (!subT.isBefore(start)) {
        if (!subT.isBefore(end)) break;
        ticks.add(_synthTick(args.noise, subT, args.offset, args.tickJitter, rng));
      }
    }
    final int jitteredMs = intervalMs +
        ((rng.nextDouble() - 0.5) * 0.5 * intervalMs).round();
    t = t.add(Duration(milliseconds: jitteredMs.clamp(50, 1 << 30)));
  }
  ticks.sort((Tick a, Tick b) => a.timestamp.compareTo(b.timestamp));
  return ticks;
}

Tick _synthTick(
  PriceNoise noise,
  DateTime t,
  double offset,
  double tickJitter,
  Random rng,
) {
  final double basePrice = noise.priceAt(t) + offset;
  final double scaledJitter = tickJitter * (basePrice.abs() * 0.001);
  final double jitter = (rng.nextDouble() - 0.5) * scaledJitter;
  final double price = (basePrice + jitter).clamp(0.0001, double.infinity);
  return Tick(
    price: double.parse(price.toStringAsFixed(_decimalsFor(price))),
    side: rng.nextBool() ? TickSide.buy : TickSide.sell,
    volume: (rng.nextInt(50) + 1).toDouble(),
    timestamp: t,
  );
}
