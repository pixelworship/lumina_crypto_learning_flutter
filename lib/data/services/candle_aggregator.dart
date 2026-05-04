import 'dart:math' as math;

import '../models/candle.dart';
import '../models/pause_gap.dart';
import '../models/tick.dart';
import '../models/timeframe.dart';

/// Pure domain logic for converting a stream of ticks into OHLC candles.
class CandleAggregator {
  const CandleAggregator();

  /// Floors a timestamp to the start of its [tf] bucket.
  DateTime bucketStart(DateTime t, Timeframe tf) {
    final int ms = t.millisecondsSinceEpoch;
    final int bucketMs = tf.duration.inMilliseconds;
    final int flooredMs = (ms ~/ bucketMs) * bucketMs;
    return DateTime.fromMillisecondsSinceEpoch(flooredMs);
  }

  /// Folds [tick] into [current], returning either the updated candle or a
  /// new candle if [tick] belongs to a later bucket.
  Candle foldTick({
    required Candle? current,
    required Tick tick,
    required Timeframe tf,
  }) {
    // Gap entries are "data unavailable" markers, not real candles —
    // never merge a tick into one. Treat as no current candle so the next
    // tick opens a fresh real candle.
    final Candle? effectiveCurrent =
        current?.isGap == true ? null : current;
    final DateTime start = bucketStart(tick.timestamp, tf);
    if (effectiveCurrent == null ||
        start.isAfter(effectiveCurrent.timestamp)) {
      return Candle(
        timestamp: start,
        open: tick.price,
        high: tick.price,
        low: tick.price,
        close: tick.price,
        volume: tick.volume,
      );
    }
    return effectiveCurrent.copyWith(
      high: tick.price > effectiveCurrent.high
          ? tick.price
          : effectiveCurrent.high,
      low: tick.price < effectiveCurrent.low
          ? tick.price
          : effectiveCurrent.low,
      close: tick.price,
      volume: effectiveCurrent.volume + tick.volume,
    );
  }

  /// Rebuilds the full candle history for [tf] from a list of [ticks].
  /// Used when the user changes timeframes.
  List<Candle> rebuild(List<Tick> ticks, Timeframe tf) {
    if (ticks.isEmpty) return const <Candle>[];
    final List<Candle> candles = <Candle>[];
    Candle? current;
    for (final Tick tick in ticks) {
      final Candle next = foldTick(current: current, tick: tick, tf: tf);
      if (current != null && next.timestamp.isAfter(current.timestamp)) {
        candles.add(current);
      }
      current = next;
    }
    if (current != null) candles.add(current);
    return candles;
  }

  /// Inserts gap (`Candle.gap`) entries into [candles] for each [PauseGap].
  ///
  /// Each gap expands into one entry per [tf] bucket it covers, so the
  /// rendered gap visually fills the time the chart was paused.
  List<Candle> mergeGaps(
    List<Candle> candles,
    List<PauseGap> gaps,
    Timeframe tf,
  ) {
    if (gaps.isEmpty) return candles;
    final int tfMs = tf.duration.inMilliseconds;
    if (tfMs <= 0) return candles;

    final List<Candle> result = <Candle>[];
    int gapIdx = 0;
    final List<Candle> realCandles =
        candles.where((Candle c) => !c.isGap).toList();

    for (final Candle candle in realCandles) {
      while (gapIdx < gaps.length &&
          !gaps[gapIdx].start.isAfter(candle.timestamp)) {
        _appendGapSlots(result, gaps[gapIdx], tf, tfMs);
        gapIdx++;
      }
      result.add(candle);
    }
    while (gapIdx < gaps.length) {
      _appendGapSlots(result, gaps[gapIdx], tf, tfMs);
      gapIdx++;
    }
    return result;
  }

  void _appendGapSlots(
    List<Candle> out,
    PauseGap gap,
    Timeframe tf,
    int tfMs,
  ) {
    final int durationMs = gap.duration.inMilliseconds;
    if (durationMs <= 0) return;
    // Cap to avoid runaway memory on very long pauses w/ tight timeframes.
    final int n = math.max(1, (durationMs / tfMs).ceil()).clamp(1, 5000);
    for (int i = 0; i < n; i++) {
      out.add(Candle.gap(timestamp: gap.start.add(tf.duration * i)));
    }
  }
}

/// Argument record for [rebuildCandlesWorker]. A record (rather than
/// a private class) so the bloc layer can construct it without
/// pulling in a separate model file.
typedef RebuildArgs = ({List<Tick> ticks, Timeframe timeframe});

/// Top-level worker for `compute`/`runOffMain`: rebuilds the full
/// candle list for a tick history. Iteration cost is `O(ticks)`, so
/// for a 24h window (~30k ticks) this is the difference between
/// dropping a frame and a smooth tap.
List<Candle> rebuildCandlesWorker(RebuildArgs args) =>
    const CandleAggregator().rebuild(args.ticks, args.timeframe);
