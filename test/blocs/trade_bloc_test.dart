import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_demo/data/models/fill.dart';
import 'package:flutter_demo/data/models/trade_pair_snapshot.dart';
import 'package:flutter_demo/data/repositories/fill_repository.dart';
import 'package:flutter_demo/data/repositories/trade_repository.dart';
import 'package:flutter_demo/data/services/asset_catalog.dart';
import 'package:flutter_demo/data/services/live_price_feed.dart';
import 'package:flutter_demo/presentation/blocs/trade/trade_bloc.dart';
import 'package:flutter_demo/presentation/blocs/trade/trade_event.dart';
import 'package:flutter_demo/presentation/blocs/trade/trade_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../fixtures/test_assets.dart';

class _MockTradeRepository extends Mock implements TradeRepository {}

LivePriceFeed _silentFeed() => LivePriceFeed(
  catalog: StaticAssetCatalog(),
  startPaused: true,
);

void main() {
  setUpAll(() {
    registerFallbackValue(ChartRange.oneDay);
  });

  late _MockTradeRepository repository;
  late LivePriceFeed priceFeed;
  late InMemoryFillRepository fillRepository;
  int idCounter = 0;

  setUp(() {
    repository = _MockTradeRepository();
    priceFeed = _silentFeed();
    fillRepository = InMemoryFillRepository();
    idCounter = 0;
  });

  tearDown(() async {
    await priceFeed.dispose();
    await fillRepository.dispose();
  });

  TradeBloc buildBloc() => TradeBloc(
    tradeRepository: repository,
    priceFeed: priceFeed,
    fillRepository: fillRepository,
    idGenerator: () => 'test-fill-${idCounter++}',
  );

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

  group('TradeBloc.TradePurchaseSubmitted', () {
    blocTest<TradeBloc, TradeState>(
      'goes through submitting → success with lastPurchaseSucceeded=true',
      setUp: () {
        when(
          () => repository.purchase(
            fromSymbol: any(named: 'fromSymbol'),
            toSymbol: any(named: 'toSymbol'),
            amount: any(named: 'amount'),
          ),
        ).thenAnswer((_) async => true);
      },
      build: buildBloc,
      act: (TradeBloc bloc) => bloc.add(
        const TradePurchaseSubmitted(
          fromSymbol: 'USDT',
          toSymbol: 'BTC',
          amount: 0.1,
        ),
      ),
      expect: () => <Matcher>[
        predicate<TradeState>(
          (TradeState s) =>
              s.isSubmittingPurchase == true &&
              s.lastPurchaseSucceeded == null,
        ),
        predicate<TradeState>(
          (TradeState s) =>
              s.isSubmittingPurchase == false &&
              s.lastPurchaseSucceeded == true,
        ),
      ],
      verify: (_) {
        verify(
          () => repository.purchase(
            fromSymbol: 'USDT',
            toSymbol: 'BTC',
            amount: 0.1,
          ),
        ).called(1);
      },
    );

    blocTest<TradeBloc, TradeState>(
      'records exactly one Fill on a successful purchase',
      setUp: () {
        when(
          () => repository.purchase(
            fromSymbol: any(named: 'fromSymbol'),
            toSymbol: any(named: 'toSymbol'),
            amount: any(named: 'amount'),
          ),
        ).thenAnswer((_) async => true);
      },
      build: buildBloc,
      act: (TradeBloc bloc) => bloc.add(
        const TradePurchaseSubmitted(
          fromSymbol: 'USDT',
          toSymbol: 'BTC',
          amount: 0.1,
        ),
      ),
      verify: (_) async {
        final List<Fill> fills = await fillRepository.getFills('BTC');
        expect(fills, hasLength(1));
        expect(fills.single.symbol, 'BTC');
        expect(fills.single.side, FillSide.buy);
        expect(fills.single.sizeBase, 0.1);
        expect(fills.single.quoteSymbol, 'USDT');
        expect(fills.single.id, 'test-fill-0');
      },
    );

    blocTest<TradeBloc, TradeState>(
      'lastPurchaseSucceeded=false when repository rejects, no fill recorded',
      setUp: () {
        when(
          () => repository.purchase(
            fromSymbol: any(named: 'fromSymbol'),
            toSymbol: any(named: 'toSymbol'),
            amount: any(named: 'amount'),
          ),
        ).thenAnswer((_) async => false);
      },
      build: buildBloc,
      act: (TradeBloc bloc) => bloc.add(
        const TradePurchaseSubmitted(
          fromSymbol: 'USDT',
          toSymbol: 'BTC',
          amount: 0.1,
        ),
      ),
      expect: () => <Matcher>[
        predicate<TradeState>(
          (TradeState s) => s.isSubmittingPurchase == true,
        ),
        predicate<TradeState>(
          (TradeState s) =>
              s.isSubmittingPurchase == false &&
              s.lastPurchaseSucceeded == false,
        ),
      ],
      verify: (_) async {
        final List<Fill> fills = await fillRepository.getFills('BTC');
        expect(fills, isEmpty,
            reason: 'rejected purchases must not record a fill');
      },
    );

    blocTest<TradeBloc, TradeState>(
      'lastPurchaseSucceeded=false + error surfaced when repo throws, '
      'no fill recorded',
      setUp: () {
        when(
          () => repository.purchase(
            fromSymbol: any(named: 'fromSymbol'),
            toSymbol: any(named: 'toSymbol'),
            amount: any(named: 'amount'),
          ),
        ).thenThrow(Exception('network'));
      },
      build: buildBloc,
      act: (TradeBloc bloc) => bloc.add(
        const TradePurchaseSubmitted(
          fromSymbol: 'USDT',
          toSymbol: 'BTC',
          amount: 0.1,
        ),
      ),
      expect: () => <Matcher>[
        predicate<TradeState>(
          (TradeState s) => s.isSubmittingPurchase == true,
        ),
        predicate<TradeState>(
          (TradeState s) =>
              s.isSubmittingPurchase == false &&
              s.lastPurchaseSucceeded == false &&
              s.errorMessage != null,
        ),
      ],
      verify: (_) async {
        final List<Fill> fills = await fillRepository.getFills('BTC');
        expect(fills, isEmpty,
            reason: 'thrown purchases must not record a fill');
      },
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

  group('TradeBloc debug price offset propagation', () {
    test(
      'live price absorbs the dial; the 24h anchor stays put so the '
      'change pill reflects the spike (real-world pump semantics)',
      () async {
        when(
          () => repository.getPair(
            baseSymbol: any(named: 'baseSymbol'),
            quoteSymbol: any(named: 'quoteSymbol'),
            range: any(named: 'range'),
          ),
        ).thenAnswer((_) async => TestAssets.tradePair);

        final TradeBloc bloc = buildBloc();
        addTearDown(bloc.close);

        bloc.add(
          const TradeRequested(baseSymbol: 'BTC', quoteSymbol: 'USDT'),
        );
        await bloc.stream.firstWhere(
          (TradeState s) => s.status == TradeStatus.success,
        );

        // No-op dial so the bloc's snapshot.price reflects the live
        // feed's actual current price (not the seeded fixture value).
        priceFeed.setPriceOffset('BTC', 0);
        await Future<void>.delayed(Duration.zero);
        await pumpEventQueue();

        final TradePairSnapshot before = bloc.state.snapshot!;
        final double anchorBefore = before.priceAt24hAgo;
        final double priceBefore = before.price;

        // Dial +$1500 — live price jumps by ~$1500, but the 24h
        // anchor stays put (yesterday's price didn't actually
        // change), so the change pill jumps to reflect the spike.
        priceFeed.setPriceOffset('BTC', 1500);
        await Future<void>.delayed(Duration.zero);
        await pumpEventQueue();

        final TradePairSnapshot after = bloc.state.snapshot!;
        expect(
          after.priceAt24hAgo,
          closeTo(anchorBefore, 0.01),
          reason:
              'past anchor must NOT shift — yesterday is still yesterday',
        );
        expect(
          after.price,
          closeTo(priceBefore + 1500, 50.0),
          reason: 'live price reflects the dial event',
        );
        // Expected change pct = (newPrice - anchor) / anchor * 100.
        final double expectedPct =
            anchorBefore == 0 ? 0 : ((after.price - anchorBefore) / anchorBefore) * 100;
        expect(
          after.changePercent,
          closeTo(expectedPct, 0.5),
          reason:
              'change pct reflects the actual jump, not a uniform shift',
        );
      },
    );
  });
}
