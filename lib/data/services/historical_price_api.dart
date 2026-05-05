import 'dart:math';

import '../../core/clock/clock.dart';
import '../../core/concurrency/background.dart';
import '../../core/diagnostics/mrm_trace.dart';
import '../models/tick.dart';
import 'live_price_feed.dart';
import 'price_noise.dart';

/// Isolate-friendly offset event: same shape as [OffsetEvent] but
/// with the timestamp as int milliseconds-since-epoch so the
/// worker can do its lookup against the int millisecond timestamps
/// it's already iterating over (no per-tick `DateTime` allocation
/// inside the synthesis hot loop).
typedef _MsOffsetEvent = ({int timestampMs, double offset});

/// Converts a list of [OffsetEvent]s to [_MsOffsetEvent]s for
/// transport across the isolate boundary. Sort order is preserved
/// (the source list is sorted ascending by [OffsetEvent.timestamp];
/// converting to int timestamps preserves that order).
List<_MsOffsetEvent> _msEvents(List<OffsetEvent> events) {
  if (events.isEmpty) return const <_MsOffsetEvent>[];
  return <_MsOffsetEvent>[
    for (final OffsetEvent e in events)
      (timestampMs: e.timestamp.millisecondsSinceEpoch, offset: e.offset),
  ];
}

/// Returns the offset that was active at [tMs], by walking [events]
/// in order and taking the latest event whose timestamp is `<= tMs`.
/// Linear walk is fine — event lists are tiny (a handful of user
/// dials per session) and a binary search would lose against the
/// constant-factor savings of an in-cache linear scan at this size.
double _offsetAtMs(List<_MsOffsetEvent> events, int tMs) {
  if (events.isEmpty) return 0;
  double offset = 0;
  for (int i = 0; i < events.length; i++) {
    if (events[i].timestampMs > tMs) break;
    offset = events[i].offset;
  }
  return offset;
}

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

  /// Returns a [sampleCount]-wide list of evenly-spaced *prices*
  /// across `[start, end)` for [symbol].
  ///
  /// Specialized for sparkline-shaped consumers (markets-list rows,
  /// portfolio mini-charts, balance card trail) that only need a
  /// dozen-or-so points to draw a curve, not the full historical
  /// tick stream. Implementations are expected to do the synthesis
  /// AND the down-sampling on a background isolate (or equivalent),
  /// so the main thread never sees the intermediate 10k-tick array
  /// or the per-tick allocations — only the final list of doubles
  /// crosses the isolate boundary.
  ///
  /// Same `[start, end)` semantics as [fetchTicks]; same offset
  /// semantics as the live feed (offset is baked into the returned
  /// prices).
  Future<List<double>> fetchSparklineSamples({
    required String symbol,
    required DateTime start,
    required DateTime end,
    required int sampleCount,
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
    // Snapshot the per-symbol offset history at dispatch time so the
    // worker can apply the offset that was active at EACH synthesized
    // tick's timestamp — not the current dial value. This is what
    // makes a "+ $50 right now" press render as a clean step at the
    // moment of the press: ticks in the past keep their original
    // (pre-event) price; ticks at or after the event timestamp pick
    // up the new offset.
    final _SynthArgs args = (
      noise: noise,
      startMs: start.millisecondsSinceEpoch,
      endMs: end.millisecondsSinceEpoch,
      nowMs: _clock.now().millisecondsSinceEpoch,
      offsetEvents: _msEvents(_feed.offsetEvents(symbol)),
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

  /// Same synthesis pipeline as [fetchTicks], but returns only the
  /// downsampled headline prices — synthesizing AND down-sampling
  /// inside the isolate so the main thread never deserializes the
  /// intermediate tick array. For a 24h sparkline window this turns
  /// a ~30k Tick payload into a single small `List<double>`.
  @override
  Future<List<double>> fetchSparklineSamples({
    required String symbol,
    required DateTime start,
    required DateTime end,
    required int sampleCount,
  }) async {
    MrmTrace.mark(70, 'Api.fetchSparklineSamples start',
        'symbol=$symbol samples=$sampleCount');
    final PriceNoise? noise = _feed.noiseFor(symbol);
    if (noise == null || !end.isAfter(start) || sampleCount <= 0) {
      return const <double>[];
    }
    if (_latency > Duration.zero) {
      await Future<void>.delayed(_latency);
    }
    MrmTrace.mark(71, 'Api sparkline latency done');
    final _SynthArgs args = (
      noise: noise,
      startMs: start.millisecondsSinceEpoch,
      endMs: end.millisecondsSinceEpoch,
      nowMs: _clock.now().millisecondsSinceEpoch,
      offsetEvents: _msEvents(_feed.offsetEvents(symbol)),
      tickJitter: _tickJitter,
      randomSeed: _random.nextInt(1 << 32),
    );
    final int estimatedTicks = _estimateTickCount(start, end, args.nowMs);
    MrmTrace.mark(72, 'Api sparkline synth dispatch',
        'estimated=$estimatedTicks isolate=${estimatedTicks >= 2000}');
    final List<double> samples =
        await runOffMain<_SparklineSynthArgs, List<double>>(
      _synthesizeSparklineSamplesWorker,
      (synth: args, sampleCount: sampleCount),
      heuristicSize: estimatedTicks,
      debugLabel: 'historical-sparkline-$symbol',
    );
    MrmTrace.mark(73, 'Api sparkline done', 'samples=${samples.length}');
    return samples;
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
  List<_MsOffsetEvent> offsetEvents,
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
        // Per-tick offset: the offset that was active AT subT,
        // not the current dial value. Past ticks (subT before any
        // dial event) get 0; ticks AT or AFTER a dial event get
        // that event's offset — producing a clean step in the
        // synthesized history at the moment of the press.
        final double offset = _offsetAtMs(
          args.offsetEvents,
          subT.millisecondsSinceEpoch,
        );
        ticks.add(_synthTick(args.noise, subT, offset, args.tickJitter, rng));
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

/// Argument record for [_synthesizeSparklineSamplesWorker]: the same
/// synth args [_synthesizeTicksWorker] takes, plus the desired
/// sample count.
typedef _SparklineSynthArgs = ({_SynthArgs synth, int sampleCount});

/// Top-level isolate worker: synthesizes the full historical tick
/// stream for a symbol/range, then immediately down-samples it to a
/// list of [args.sampleCount] evenly-spaced prices. Both passes run
/// in the same isolate so the only thing that crosses the isolate
/// boundary back to the main thread is the small `List<double>`
/// — never the full 10k–30k Tick array.
List<double> _synthesizeSparklineSamplesWorker(_SparklineSynthArgs args) {
  final List<Tick> ticks = _synthesizeTicksWorker(args.synth);
  final int target = args.sampleCount;
  if (ticks.isEmpty || target <= 0) return const <double>[];
  if (ticks.length <= target) {
    return <double>[for (final Tick t in ticks) t.price];
  }
  final List<double> result = List<double>.filled(target, 0.0);
  // (target-1) gives endpoints aligned with first + last tick so the
  // seeded shape spans the full window edge-to-edge.
  final double scale = (ticks.length - 1) / (target - 1);
  for (int i = 0; i < target; i++) {
    final int idx = (i * scale).round();
    result[i] = ticks[idx].price;
  }
  return result;
}
