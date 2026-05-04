import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_demo/data/models/crypto_asset.dart';
import 'package:flutter_demo/data/repositories/market_repository.dart';
import 'package:flutter_demo/data/repositories/portfolio_repository.dart';
import 'package:flutter_demo/data/services/asset_catalog.dart';
import 'package:flutter_demo/data/services/live_price_feed.dart';
import 'package:flutter_demo/presentation/blocs/home/home_bloc.dart';
import 'package:flutter_demo/presentation/blocs/home/home_event.dart';
import 'package:flutter_demo/presentation/blocs/home/home_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../fixtures/test_assets.dart';

class _MockPortfolioRepository extends Mock implements PortfolioRepository {}

class _MockMarketRepository extends Mock implements MarketRepository {}

/// Spins up a paused [LivePriceFeed] so the bloc's subscription
/// doesn't fire spurious `_PricesUpdated` events that would interfere
/// with `expect:` assertions.
LivePriceFeed _silentFeed() => LivePriceFeed(
  catalog: StaticAssetCatalog(),
  startPaused: true,
);

void main() {
  late _MockPortfolioRepository portfolioRepository;
  late _MockMarketRepository marketRepository;
  late LivePriceFeed priceFeed;

  setUp(() {
    portfolioRepository = _MockPortfolioRepository();
    marketRepository = _MockMarketRepository();
    priceFeed = _silentFeed();
  });

  tearDown(() async {
    await priceFeed.dispose();
  });

  HomeBloc buildBloc() => HomeBloc(
    portfolioRepository: portfolioRepository,
    marketRepository: marketRepository,
    priceFeed: priceFeed,
  );

  group('HomeBloc.HomeRequested', () {
    blocTest<HomeBloc, HomeState>(
      'emits loading then success with balance + watchlist on happy path',
      setUp: () {
        when(
          portfolioRepository.getBalanceSummary,
        ).thenAnswer((_) async => TestAssets.balance);
        when(
          portfolioRepository.getPortfolio,
        ).thenAnswer((_) async => TestAssets.portfolio);
        when(
          marketRepository.getWatchlist,
        ).thenAnswer((_) async => TestAssets.watchlist);
      },
      build: buildBloc,
      act: (HomeBloc bloc) => bloc.add(const HomeRequested()),
      expect: () => <Matcher>[
        predicate<HomeState>((HomeState s) => s.status == HomeStatus.loading),
        predicate<HomeState>(
          (HomeState s) =>
              s.status == HomeStatus.success &&
              s.balance == TestAssets.balance &&
              s.watchlist.length == TestAssets.watchlist.length,
        ),
      ],
      verify: (_) {
        verify(portfolioRepository.getBalanceSummary).called(1);
        verify(marketRepository.getWatchlist).called(1);
      },
    );

    blocTest<HomeBloc, HomeState>(
      'emits loading then failure when balance call throws',
      setUp: () {
        when(
          portfolioRepository.getBalanceSummary,
        ).thenThrow(Exception('boom'));
        when(
          portfolioRepository.getPortfolio,
        ).thenAnswer((_) async => TestAssets.portfolio);
        when(
          marketRepository.getWatchlist,
        ).thenAnswer((_) async => <CryptoQuote>[]);
      },
      build: buildBloc,
      act: (HomeBloc bloc) => bloc.add(const HomeRequested()),
      expect: () => <Matcher>[
        predicate<HomeState>((HomeState s) => s.status == HomeStatus.loading),
        predicate<HomeState>(
          (HomeState s) =>
              s.status == HomeStatus.failure && s.errorMessage != null,
        ),
      ],
    );

    blocTest<HomeBloc, HomeState>(
      'emits loading then failure when watchlist call throws',
      setUp: () {
        when(portfolioRepository.getBalanceSummary).thenAnswer(
          (_) async => TestAssets.balance,
        );
        when(
          portfolioRepository.getPortfolio,
        ).thenAnswer((_) async => TestAssets.portfolio);
        when(marketRepository.getWatchlist).thenThrow(StateError('offline'));
      },
      build: buildBloc,
      act: (HomeBloc bloc) => bloc.add(const HomeRequested()),
      expect: () => <Matcher>[
        predicate<HomeState>((HomeState s) => s.status == HomeStatus.loading),
        predicate<HomeState>(
          (HomeState s) => s.status == HomeStatus.failure,
        ),
      ],
    );
  });

  group('HomeBloc.HomeRefreshed', () {
    blocTest<HomeBloc, HomeState>(
      'reloads without going through a loading state and clears prior error',
      setUp: () {
        when(
          portfolioRepository.getBalanceSummary,
        ).thenAnswer((_) async => TestAssets.balance);
        when(
          portfolioRepository.getPortfolio,
        ).thenAnswer((_) async => TestAssets.portfolio);
        when(
          marketRepository.getWatchlist,
        ).thenAnswer((_) async => TestAssets.watchlist);
      },
      build: buildBloc,
      seed: () => const HomeState(
        status: HomeStatus.failure,
        errorMessage: 'previous failure',
      ),
      act: (HomeBloc bloc) => bloc.add(const HomeRefreshed()),
      expect: () => <Matcher>[
        predicate<HomeState>(
          (HomeState s) =>
              s.status == HomeStatus.success &&
              s.balance == TestAssets.balance &&
              s.watchlist.length == TestAssets.watchlist.length &&
              s.errorMessage == null,
        ),
      ],
    );

    blocTest<HomeBloc, HomeState>(
      'transitions success → failure when refresh fails',
      setUp: () {
        when(
          portfolioRepository.getBalanceSummary,
        ).thenThrow(Exception('boom'));
        when(
          portfolioRepository.getPortfolio,
        ).thenAnswer((_) async => TestAssets.portfolio);
      },
      build: buildBloc,
      seed: () => HomeState(
        status: HomeStatus.success,
        balance: TestAssets.balance,
        watchlist: TestAssets.watchlist,
      ),
      act: (HomeBloc bloc) => bloc.add(const HomeRefreshed()),
      expect: () => <Matcher>[
        predicate<HomeState>(
          (HomeState s) => s.status == HomeStatus.failure,
        ),
      ],
    );
  });

  group('HomeBloc.HomeQuickActionTriggered', () {
    test('deposit action calls deposit on the portfolio repository', () async {
      when(
        () => portfolioRepository.deposit(any()),
      ).thenAnswer((_) async => true);
      final HomeBloc bloc = buildBloc();

      bloc.add(
        const HomeQuickActionTriggered(HomeQuickAction.deposit),
      );
      await Future<void>.delayed(Duration.zero);

      verify(() => portfolioRepository.deposit(0)).called(1);
      await bloc.close();
    });

    test('withdraw action calls withdraw on the portfolio repository', () async {
      when(
        () => portfolioRepository.withdraw(any()),
      ).thenAnswer((_) async => true);
      final HomeBloc bloc = buildBloc();

      bloc.add(
        const HomeQuickActionTriggered(HomeQuickAction.withdraw),
      );
      await Future<void>.delayed(Duration.zero);

      verify(() => portfolioRepository.withdraw(0)).called(1);
      await bloc.close();
    });

    test('swap action does not touch portfolio repository', () async {
      final HomeBloc bloc = buildBloc();

      bloc.add(
        const HomeQuickActionTriggered(HomeQuickAction.swap),
      );
      await Future<void>.delayed(Duration.zero);

      verifyNever(() => portfolioRepository.deposit(any()));
      verifyNever(() => portfolioRepository.withdraw(any()));
      await bloc.close();
    });
  });

  group('HomeBloc initial state', () {
    test('starts in HomeStatus.initial with no balance or watchlist', () {
      final HomeBloc bloc = buildBloc();

      expect(bloc.state.status, HomeStatus.initial);
      expect(bloc.state.balance, isNull);
      expect(bloc.state.watchlist, isEmpty);
      expect(bloc.state.errorMessage, isNull);

      bloc.close();
    });
  });
}
