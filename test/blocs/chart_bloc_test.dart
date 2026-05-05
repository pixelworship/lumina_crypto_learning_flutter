import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_demo/data/models/fill.dart';
import 'package:flutter_demo/data/models/market_event.dart';
import 'package:flutter_demo/data/models/tick.dart';
import 'package:flutter_demo/data/repositories/chart_events_repository.dart';
import 'package:flutter_demo/data/repositories/fill_repository.dart';
import 'package:flutter_demo/data/repositories/historical_tick_repository.dart';
import 'package:flutter_demo/data/repositories/tick_repository.dart';
import 'package:flutter_demo/data/services/chart_events_api.dart';
import 'package:flutter_demo/presentation/blocs/chart/chart_bloc.dart';
import 'package:flutter_demo/presentation/blocs/chart/chart_event.dart';
import 'package:flutter_demo/presentation/blocs/chart/chart_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockTickRepository extends Mock implements TickRepository {}

class _MockHistoricalTickRepository extends Mock
    implements HistoricalTickRepository {}

/// Always returns an empty list — the chart_bloc tests below assert on
/// fills, not events, so we just need both network calls (the window
/// fetch on initial load + the delta fetch from the 1s poller) to
/// no-op without making real HTTP requests.
class _StubChartEventsApi implements ChartEventsApi {
  @override
  Future<List<MarketEvent>> fetchEventsInRange({
    required String symbol,
    required DateTime from,
    required DateTime to,
    int limit = 200,
  }) async {
    return const <MarketEvent>[];
  }

  @override
  Future<List<MarketEvent>> fetchEventsSince({
    required String symbol,
    required DateTime since,
    int limit = 500,
  }) async {
    return const <MarketEvent>[];
  }
}

DateTime _at(int hour) => DateTime.utc(2026, 5, 3, hour);

Fill _fill({
  required String id,
  required String symbol,
  int hour = 1,
  double price = 100,
}) {
  return Fill(
    id: id,
    symbol: symbol,
    side: FillSide.buy,
    price: price,
    sizeBase: 0.1,
    costQuote: price * 0.1,
    quoteSymbol: 'USDT',
    timestamp: _at(hour),
  );
}

void main() {
  late _MockTickRepository tickRepo;
  late _MockHistoricalTickRepository historicalRepo;
  late InMemoryFillRepository fillRepo;
  late ChartEventsRepository eventsRepo;
  late StreamController<Tick> tickController;

  setUp(() {
    tickRepo = _MockTickRepository();
    historicalRepo = _MockHistoricalTickRepository();
    fillRepo = InMemoryFillRepository();
    eventsRepo = ChartEventsRepository(api: _StubChartEventsApi());
    tickController = StreamController<Tick>.broadcast();

    when(() => tickRepo.watchTicks(any())).thenAnswer(
      (_) => tickController.stream,
    );
    // Default to a 0 offset; individual tests override via `when(...)`
    // when they need to simulate a feed that already has a debug
    // offset dialed in (e.g. carried over from a previous chart-route
    // session under the shared, app-scoped LivePriceFeed).
    when(() => tickRepo.priceOffset(any())).thenReturn(0.0);
    // Empty history is enough for the fill-focused tests below.
    when(
      () => historicalRepo.fetchTicks(
        symbol: any(named: 'symbol'),
        start: any(named: 'start'),
        end: any(named: 'end'),
      ),
    ).thenAnswer((_) async => const <Tick>[]);
    when(
      () => historicalRepo.peekTicks(
        symbol: any(named: 'symbol'),
        start: any(named: 'start'),
        end: any(named: 'end'),
      ),
    ).thenReturn(const <Tick>[]);
  });

  tearDown(() async {
    await tickController.close();
    await fillRepo.dispose();
  });

  ChartBloc buildBloc({String initialSymbol = 'BTC'}) => ChartBloc(
        repository: tickRepo,
        historicalRepository: historicalRepo,
        fillRepository: fillRepo,
        eventsRepository: eventsRepo,
        initialSymbol: initialSymbol,
        // The events stub returns [] for both shapes; we don't need
        // the poller for these tests and a periodic timer would leak
        // past the harness.
        eventPollInterval: null,
      );

  group('ChartBloc fills hydration', () {
    blocTest<ChartBloc, ChartState>(
      'hydrates state.fills from FillRepository on ChartStarted',
      setUp: () async {
        // Prime the repo with two pre-existing BTC fills before the
        // bloc subscribes, so the very first emission of `state.fills`
        // already reflects them.
        await fillRepo.recordFill(_fill(id: 'a', symbol: 'BTC', hour: 1));
        await fillRepo.recordFill(_fill(id: 'b', symbol: 'BTC', hour: 2));
      },
      build: buildBloc,
      act: (ChartBloc bloc) => bloc.add(const ChartStarted(symbol: 'BTC')),
      // The bloc emits multiple intermediate states (loading,
      // candles, etc); we just care that *eventually* one of them
      // contains both pre-recorded fills.
      wait: const Duration(milliseconds: 50),
      verify: (ChartBloc bloc) {
        expect(
          bloc.state.fills.map((Fill f) => f.id).toList(),
          <String>['a', 'b'],
        );
      },
    );

    blocTest<ChartBloc, ChartState>(
      'broadcasts subsequent recordFill calls into state.fills',
      build: buildBloc,
      act: (ChartBloc bloc) async {
        bloc.add(const ChartStarted(symbol: 'BTC'));
        // Let the bloc finish initial hydration before recording.
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await fillRepo.recordFill(_fill(id: 'live', symbol: 'BTC', hour: 3));
      },
      wait: const Duration(milliseconds: 80),
      verify: (ChartBloc bloc) {
        expect(
          bloc.state.fills.map((Fill f) => f.id).toList(),
          contains('live'),
        );
      },
    );

    blocTest<ChartBloc, ChartState>(
      'ignores fills for a different symbol',
      setUp: () async {
        await fillRepo.recordFill(_fill(id: 'eth-a', symbol: 'ETH', hour: 1));
      },
      build: buildBloc,
      act: (ChartBloc bloc) => bloc.add(const ChartStarted(symbol: 'BTC')),
      wait: const Duration(milliseconds: 50),
      verify: (ChartBloc bloc) {
        expect(bloc.state.fills, isEmpty);
      },
    );
  });

  group('ChartBloc symbol switch resubscribe', () {
    blocTest<ChartBloc, ChartState>(
      'switches the fills subscription to the new symbol',
      setUp: () async {
        await fillRepo.recordFill(_fill(id: 'btc-a', symbol: 'BTC', hour: 1));
        await fillRepo.recordFill(_fill(id: 'eth-a', symbol: 'ETH', hour: 1));
      },
      build: buildBloc,
      act: (ChartBloc bloc) async {
        bloc.add(const ChartStarted(symbol: 'BTC'));
        await Future<void>.delayed(const Duration(milliseconds: 30));
        bloc.add(const ChartSymbolChanged('ETH'));
      },
      wait: const Duration(milliseconds: 100),
      verify: (ChartBloc bloc) {
        expect(bloc.state.symbol, 'ETH');
        expect(
          bloc.state.fills.map((Fill f) => f.id).toList(),
          <String>['eth-a'],
        );
      },
    );

    blocTest<ChartBloc, ChartState>(
      'symbol switch clears the previous symbol\'s fills before new ones land',
      setUp: () async {
        await fillRepo.recordFill(_fill(id: 'btc-a', symbol: 'BTC', hour: 1));
      },
      build: buildBloc,
      act: (ChartBloc bloc) async {
        bloc.add(const ChartStarted(symbol: 'BTC'));
        await Future<void>.delayed(const Duration(milliseconds: 30));
        bloc.add(const ChartSymbolChanged('SOL'));
      },
      wait: const Duration(milliseconds: 100),
      verify: (ChartBloc bloc) {
        expect(bloc.state.symbol, 'SOL');
        expect(bloc.state.fills, isEmpty);
      },
    );
  });

  group('ChartBloc price offset / feed desync', () {
    // Regression: chart bloc is route-scoped but the `LivePriceFeed`
    // is app-scoped. After the user dials a debug offset and then
    // navigates away + back, a fresh chart bloc is constructed with
    // `state.priceOffset == 0` while the feed still reports the
    // previously-dialed value. The next `PriceOffsetChanged` event
    // must therefore be evaluated against the FEED's current offset
    // — not against the (stale) `state.priceOffset` — so we
    // increment rather than overwrite.
    blocTest<ChartBloc, ChartState>(
      'seeds state.priceOffset from the feed on ChartStarted',
      setUp: () {
        when(() => tickRepo.priceOffset('BTC')).thenReturn(750.0);
      },
      build: buildBloc,
      act: (ChartBloc bloc) => bloc.add(const ChartStarted(symbol: 'BTC')),
      wait: const Duration(milliseconds: 50),
      verify: (ChartBloc bloc) {
        expect(bloc.state.priceOffset, 750.0);
      },
    );

    blocTest<ChartBloc, ChartState>(
      're-syncs state.priceOffset on ChartSymbolChanged',
      setUp: () {
        // BTC starts unmarked; ETH already has a $250 offset dialed
        // (e.g. carried from a different chart-route session under
        // the same app-scoped feed).
        when(() => tickRepo.priceOffset('BTC')).thenReturn(0.0);
        when(() => tickRepo.priceOffset('ETH')).thenReturn(250.0);
      },
      build: buildBloc,
      act: (ChartBloc bloc) async {
        bloc.add(const ChartStarted(symbol: 'BTC'));
        await Future<void>.delayed(const Duration(milliseconds: 30));
        bloc.add(const ChartSymbolChanged('ETH'));
      },
      wait: const Duration(milliseconds: 100),
      verify: (ChartBloc bloc) {
        expect(bloc.state.symbol, 'ETH');
        expect(bloc.state.priceOffset, 250.0);
      },
    );

    test(
      'PriceOffsetChanged increments — not overwrites — the feed offset '
      'when state.priceOffset starts at 0 but the feed already holds a '
      'previously-dialed value',
      () async {
        // Feed reports a $750 offset already baked in (carried over
        // from a prior chart-route session under the shared app-scoped
        // feed); the new chart bloc starts unaware of it.
        when(() => tickRepo.priceOffset('BTC')).thenReturn(750.0);

        final ChartBloc bloc = buildBloc();
        bloc.add(const ChartStarted(symbol: 'BTC'));
        await Future<void>.delayed(const Duration(milliseconds: 30));

        // After start, the bloc must mirror the feed's actual offset
        // (so the UI's "current offset" indicator + the +/- step math
        // both align with reality).
        expect(bloc.state.priceOffset, 750.0);

        // User clicks the "+25" debug button — UI sends `current + step`.
        bloc.add(const PriceOffsetChanged(775.0));
        await Future<void>.delayed(const Duration(milliseconds: 50));

        // The feed now holds $775 (incremented by $25), NOT $25 (which
        // was the bug — the chart bloc would overwrite the feed value
        // with the small UI delta, dropping the absolute price by $725
        // and causing the "graph spikes up briefly then collapses" bug).
        verify(() => tickRepo.setPriceOffset('BTC', 775.0)).called(1);
        expect(bloc.state.priceOffset, 775.0);

        await bloc.close();
      },
    );
  });

  group('ChartBloc fills lifecycle', () {
    test('cancels fills subscription on close so further fills do not '
        'leak into a disposed bloc', () async {
      final ChartBloc bloc = buildBloc();
      bloc.add(const ChartStarted(symbol: 'BTC'));
      await Future<void>.delayed(const Duration(milliseconds: 30));

      await bloc.close();

      // Recording after close must not blow up; the bloc is gone, so
      // we just verify the recordFill call still resolves cleanly
      // against the repository.
      await expectLater(
        fillRepo.recordFill(_fill(id: 'late', symbol: 'BTC', hour: 5)),
        completes,
      );
    });
  });
}
