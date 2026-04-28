import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_demo/data/models/trade_pair_snapshot.dart';
import 'package:flutter_demo/data/repositories/trade_repository.dart';
import 'package:flutter_demo/presentation/blocs/trade/trade_bloc.dart';
import 'package:flutter_demo/presentation/blocs/trade/trade_event.dart';
import 'package:flutter_demo/presentation/blocs/trade/trade_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../fixtures/test_assets.dart';

class _MockTradeRepository extends Mock implements TradeRepository {}

void main() {
  setUpAll(() {
    registerFallbackValue(ChartRange.oneDay);
  });

  late _MockTradeRepository repository;

  setUp(() {
    repository = _MockTradeRepository();
  });

  TradeBloc buildBloc() => TradeBloc(tradeRepository: repository);

  group('TradeBloc.TradeRequested', () {
    blocTest<TradeBloc, TradeState>(
      'emits loading then success with the requested pair',
      setUp: () {
        when(
          () => repository.getPair(
            baseSymbol: any(named: 'baseSymbol'),
            quoteSymbol: any(named: 'quoteSymbol'),
            range: any(named: 'range'),
          ),
        ).thenAnswer((_) async => TestAssets.tradePair);
      },
      build: buildBloc,
      act: (TradeBloc bloc) => bloc.add(
        const TradeRequested(baseSymbol: 'BTC', quoteSymbol: 'USDT'),
      ),
      expect: () => <Matcher>[
        predicate<TradeState>(
          (TradeState s) =>
              s.status == TradeStatus.loading &&
              s.baseSymbol == 'BTC' &&
              s.quoteSymbol == 'USDT',
        ),
        predicate<TradeState>(
          (TradeState s) =>
              s.status == TradeStatus.success &&
              s.snapshot == TestAssets.tradePair,
        ),
      ],
      verify: (_) {
        verify(
          () => repository.getPair(
            baseSymbol: 'BTC',
            quoteSymbol: 'USDT',
            range: ChartRange.oneDay,
          ),
        ).called(1);
      },
    );

    blocTest<TradeBloc, TradeState>(
      'emits failure when repository throws',
      setUp: () {
        when(
          () => repository.getPair(
            baseSymbol: any(named: 'baseSymbol'),
            quoteSymbol: any(named: 'quoteSymbol'),
            range: any(named: 'range'),
          ),
        ).thenThrow(Exception('boom'));
      },
      build: buildBloc,
      act: (TradeBloc bloc) => bloc.add(const TradeRequested()),
      expect: () => <Matcher>[
        predicate<TradeState>(
          (TradeState s) => s.status == TradeStatus.loading,
        ),
        predicate<TradeState>(
          (TradeState s) =>
              s.status == TradeStatus.failure && s.errorMessage != null,
        ),
      ],
    );
  });

  group('TradeBloc.TradeRangeChanged', () {
    blocTest<TradeBloc, TradeState>(
      'updates range, fires loading, then re-fetches with the new range',
      setUp: () {
        when(
          () => repository.getPair(
            baseSymbol: any(named: 'baseSymbol'),
            quoteSymbol: any(named: 'quoteSymbol'),
            range: any(named: 'range'),
          ),
        ).thenAnswer((_) async => TestAssets.tradePair);
      },
      build: buildBloc,
      seed: () => TradeState(
        status: TradeStatus.success,
        snapshot: TestAssets.tradePair,
        baseSymbol: 'BTC',
        quoteSymbol: 'USDT',
      ),
      act: (TradeBloc bloc) =>
          bloc.add(const TradeRangeChanged(ChartRange.oneWeek)),
      expect: () => <Matcher>[
        predicate<TradeState>(
          (TradeState s) =>
              s.status == TradeStatus.loading &&
              s.range == ChartRange.oneWeek,
        ),
        predicate<TradeState>(
          (TradeState s) => s.status == TradeStatus.success,
        ),
      ],
      verify: (_) {
        verify(
          () => repository.getPair(
            baseSymbol: 'BTC',
            quoteSymbol: 'USDT',
            range: ChartRange.oneWeek,
          ),
        ).called(1);
      },
    );
  });

  group('TradeBloc.TradeSwapSubmitted', () {
    blocTest<TradeBloc, TradeState>(
      'goes through submitting → success with lastSwapSucceeded=true',
      setUp: () {
        when(
          () => repository.swap(
            fromSymbol: any(named: 'fromSymbol'),
            toSymbol: any(named: 'toSymbol'),
            amount: any(named: 'amount'),
          ),
        ).thenAnswer((_) async => true);
      },
      build: buildBloc,
      act: (TradeBloc bloc) => bloc.add(
        const TradeSwapSubmitted(
          fromSymbol: 'BTC',
          toSymbol: 'USDT',
          amount: 0.1,
        ),
      ),
      expect: () => <Matcher>[
        predicate<TradeState>(
          (TradeState s) =>
              s.isSubmittingSwap == true && s.lastSwapSucceeded == null,
        ),
        predicate<TradeState>(
          (TradeState s) =>
              s.isSubmittingSwap == false && s.lastSwapSucceeded == true,
        ),
      ],
      verify: (_) {
        verify(
          () => repository.swap(
            fromSymbol: 'BTC',
            toSymbol: 'USDT',
            amount: 0.1,
          ),
        ).called(1);
      },
    );

    blocTest<TradeBloc, TradeState>(
      'lastSwapSucceeded=false when repository rejects the swap',
      setUp: () {
        when(
          () => repository.swap(
            fromSymbol: any(named: 'fromSymbol'),
            toSymbol: any(named: 'toSymbol'),
            amount: any(named: 'amount'),
          ),
        ).thenAnswer((_) async => false);
      },
      build: buildBloc,
      act: (TradeBloc bloc) => bloc.add(
        const TradeSwapSubmitted(
          fromSymbol: 'BTC',
          toSymbol: 'USDT',
          amount: 0.1,
        ),
      ),
      expect: () => <Matcher>[
        predicate<TradeState>((TradeState s) => s.isSubmittingSwap == true),
        predicate<TradeState>(
          (TradeState s) =>
              s.isSubmittingSwap == false && s.lastSwapSucceeded == false,
        ),
      ],
    );

    blocTest<TradeBloc, TradeState>(
      'sets lastSwapSucceeded=false and surfaces error when repo throws',
      setUp: () {
        when(
          () => repository.swap(
            fromSymbol: any(named: 'fromSymbol'),
            toSymbol: any(named: 'toSymbol'),
            amount: any(named: 'amount'),
          ),
        ).thenThrow(Exception('network'));
      },
      build: buildBloc,
      act: (TradeBloc bloc) => bloc.add(
        const TradeSwapSubmitted(
          fromSymbol: 'BTC',
          toSymbol: 'USDT',
          amount: 0.1,
        ),
      ),
      expect: () => <Matcher>[
        predicate<TradeState>((TradeState s) => s.isSubmittingSwap == true),
        predicate<TradeState>(
          (TradeState s) =>
              s.isSubmittingSwap == false &&
              s.lastSwapSucceeded == false &&
              s.errorMessage != null,
        ),
      ],
    );
  });

  group('TradeBloc initial state', () {
    test('starts on BTC/USDT with the 1D range', () {
      final TradeBloc bloc = buildBloc();
      expect(bloc.state.baseSymbol, 'BTC');
      expect(bloc.state.quoteSymbol, 'USDT');
      expect(bloc.state.range, ChartRange.oneDay);
      expect(bloc.state.status, TradeStatus.initial);
      bloc.close();
    });
  });
}
