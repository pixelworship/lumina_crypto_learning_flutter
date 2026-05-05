import 'package:flutter_demo/data/models/candle.dart';
import 'package:flutter_demo/data/models/pause_gap.dart';
import 'package:flutter_demo/data/models/tick.dart';
import 'package:flutter_demo/data/models/timeframe.dart';
import 'package:flutter_demo/data/services/candle_aggregator.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime _at(int minute) => DateTime.utc(2026, 5, 3, 12, minute);

Tick _tick(int minute, {double price = 100, double volume = 1}) => Tick(
      price: price,
      side: TickSide.buy,
      volume: volume,
      timestamp: _at(minute),
    );

void main() {
  group('rebuildCandlesWorker', () {
    // The chart bloc dispatches this worker to a background isolate
    // to keep candle rebuilds off the main thread. The worker now
    // also folds in pause-gap markers in the same hop — previously
    // the bloc rebuilt off-main and then ran mergeGaps on the main
    // thread, which doubled the per-frame cost. These tests pin the
    // worker's behavior so a future refactor can't silently regress
    // either pass.

    test('rebuilds candles for a tick stream when no gaps are passed',
        () {
      final List<Tick> ticks = <Tick>[
        _tick(0, price: 100),
        _tick(0, price: 110),
        _tick(1, price: 105),
      ];
      final List<Candle> candles = rebuildCandlesWorker((
        ticks: ticks,
        timeframe: Timeframe.m1,
        gaps: const <PauseGap>[],
      ));
      expect(candles, hasLength(2));
      expect(candles[0].open, 100);
      expect(candles[0].high, 110);
      expect(candles[0].close, 110);
      expect(candles[1].open, 105);
      expect(candles.every((Candle c) => !c.isGap), isTrue);
    });

    test(
      'splices gap markers in the same hop when gaps are passed',
      () {
        // 3 minutes of gap between two real candles.
        final List<Tick> ticks = <Tick>[
          _tick(0, price: 100),
          _tick(5, price: 120),
        ];
        final PauseGap gap = PauseGap(start: _at(1), end: _at(4));
        final List<Candle> candles = rebuildCandlesWorker((
          ticks: ticks,
          timeframe: Timeframe.m1,
          gaps: <PauseGap>[gap],
        ));
        // 2 real candles + 3 gap slots (one per minute of pause).
        expect(candles.where((Candle c) => !c.isGap), hasLength(2));
        expect(candles.where((Candle c) => c.isGap), hasLength(3));
        // Gap slots should be sandwiched between the two real
        // candles, ordered chronologically.
        final List<DateTime> realTs = candles
            .where((Candle c) => !c.isGap)
            .map((Candle c) => c.timestamp)
            .toList();
        expect(realTs.first.isBefore(realTs.last), isTrue);
      },
    );

    test('returns an empty candle list for an empty tick stream', () {
      final List<Candle> candles = rebuildCandlesWorker((
        ticks: const <Tick>[],
        timeframe: Timeframe.m1,
        gaps: const <PauseGap>[],
      ));
      expect(candles, isEmpty);
    });
  });
}
