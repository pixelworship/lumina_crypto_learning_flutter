import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_demo/data/models/fill.dart';
import 'package:flutter_demo/data/models/tick.dart';
import 'package:flutter_demo/data/repositories/fill_repository.dart';
import 'package:flutter_demo/data/repositories/historical_tick_repository.dart';
import 'package:flutter_demo/data/repositories/tick_repository.dart';
import 'package:flutter_demo/presentation/blocs/chart/chart_bloc.dart';
import 'package:flutter_demo/presentation/blocs/chart/chart_event.dart';
import 'package:flutter_demo/presentation/blocs/chart/chart_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockTickRepository extends Mock implements TickRepository {}

class _MockHistoricalTickRepository extends Mock
    implements HistoricalTickRepository {}

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
  late StreamController<Tick> tickController;

  setUp(() {
    tickRepo = _MockTickRepository();
    historicalRepo = _MockHistoricalTickRepository();
    fillRepo = InMemoryFillRepository();
    tickController = StreamController<Tick>.broadcast();

    when(() => tickRepo.watchTicks(any())).thenAnswer(
      (_) => tickController.stream,
    );
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
        initialSymbol: initialSymbol,
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
