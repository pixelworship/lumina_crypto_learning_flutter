import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_demo/data/models/asset_category.dart';
import 'package:flutter_demo/data/models/crypto_asset.dart';
import 'package:flutter_demo/data/models/market_quotes_page.dart';
import 'package:flutter_demo/data/repositories/market_repository.dart';
import 'package:flutter_demo/data/services/asset_catalog.dart';
import 'package:flutter_demo/data/services/live_price_feed.dart';
import 'package:flutter_demo/presentation/blocs/markets/markets_bloc.dart';
import 'package:flutter_demo/presentation/blocs/markets/markets_event.dart';
import 'package:flutter_demo/presentation/blocs/markets/markets_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _FakeMarketRepository extends Mock implements MarketRepository {}

LivePriceFeed _silentFeed() => LivePriceFeed(
  catalog: StaticAssetCatalog(),
  startPaused: true,
);

const CryptoAsset _btc = CryptoAsset(
  id: 'btc',
  symbol: 'BTC',
  name: 'Bitcoin',
  color: Color(0xFFF7931A),
  iconLetter: 'B',
  categories: <AssetCategory>[AssetCategory.layer1],
);

const CryptoAsset _uni = CryptoAsset(
  id: 'uni',
  symbol: 'UNI',
  name: 'Uniswap',
  color: Color(0xFFFF007A),
  iconLetter: 'U',
  categories: <AssetCategory>[AssetCategory.defi],
);

const List<CryptoQuote> _seed = <CryptoQuote>[
  CryptoQuote(
    asset: _btc,
    rank: 1,
    price: 64000,
    change24hPercent: 2.4,
    change24hAbsolute: 1500,
  ),
  CryptoQuote(
    asset: _uni,
    rank: 4,
    price: 11.0,
    change24hPercent: 0.5,
    change24hAbsolute: 0.05,
  ),
];

void main() {
  late _FakeMarketRepository repository;
  late LivePriceFeed priceFeed;

  setUp(() {
    repository = _FakeMarketRepository();
    priceFeed = _silentFeed();
    when(repository.getMarketQuotes).thenAnswer((_) async => _seed);
    when(
      () => repository.getMarketQuotesPage(
        offset: any(named: 'offset'),
        limit: any(named: 'limit'),
      ),
    ).thenAnswer(
      (_) async => const MarketQuotesPage(
        quotes: _seed,
        nextOffset: 2,
        hasMore: false,
      ),
    );
  });

  tearDown(() async {
    await priceFeed.dispose();
  });

  MarketsBloc buildBloc() => MarketsBloc(
    marketRepository: repository,
    priceFeed: priceFeed,
  );

  group('MarketsBloc', () {
    blocTest<MarketsBloc, MarketsState>(
      'loads quotes on MarketsRequested',
      build: buildBloc,
      act: (MarketsBloc bloc) => bloc.add(const MarketsRequested()),
      expect: () => <Matcher>[
        predicate<MarketsState>(
          (MarketsState s) => s.status == MarketsStatus.loading,
        ),
        predicate<MarketsState>(
          (MarketsState s) =>
              s.status == MarketsStatus.success && s.quotes.length == 2,
        ),
      ],
    );

    blocTest<MarketsBloc, MarketsState>(
      'filters by DeFi category',
      build: buildBloc,
      seed: () => const MarketsState(
        status: MarketsStatus.success,
        quotes: _seed,
      ),
      act: (MarketsBloc bloc) =>
          bloc.add(const MarketsCategoryChanged(AssetCategory.defi)),
      verify: (MarketsBloc bloc) {
        expect(bloc.state.visibleQuotes, hasLength(1));
        expect(bloc.state.visibleQuotes.first.asset.symbol, 'UNI');
      },
    );

    blocTest<MarketsBloc, MarketsState>(
      'filters by search query',
      build: buildBloc,
      seed: () => const MarketsState(
        status: MarketsStatus.success,
        quotes: _seed,
      ),
      act: (MarketsBloc bloc) =>
          bloc.add(const MarketsSearchChanged('uni')),
      verify: (MarketsBloc bloc) {
        expect(bloc.state.visibleQuotes, hasLength(1));
        expect(bloc.state.visibleQuotes.first.asset.symbol, 'UNI');
      },
    );

    blocTest<MarketsBloc, MarketsState>(
      'emits failure when repository throws',
      setUp: () => when(
        () => repository.getMarketQuotesPage(
          offset: any(named: 'offset'),
          limit: any(named: 'limit'),
        ),
      ).thenThrow(Exception('boom')),
      build: buildBloc,
      act: (MarketsBloc bloc) => bloc.add(const MarketsRequested()),
      expect: () => <Matcher>[
        predicate<MarketsState>(
          (MarketsState s) => s.status == MarketsStatus.loading,
        ),
        predicate<MarketsState>(
          (MarketsState s) => s.status == MarketsStatus.failure,
        ),
      ],
    );

    blocTest<MarketsBloc, MarketsState>(
      'MarketsNextPageRequested appends paginated quotes',
      setUp: () {
        const CryptoAsset extra = CryptoAsset(
          id: 'nova',
          symbol: 'NOVA',
          name: 'Nova',
          color: Color(0xFF4ADE80),
          iconLetter: 'N',
          categories: <AssetCategory>[AssetCategory.defi],
        );
        when(
          () => repository.getMarketQuotesPage(offset: 2, limit: any(named: 'limit')),
        ).thenAnswer(
          (_) async => const MarketQuotesPage(
            quotes: <CryptoQuote>[
              CryptoQuote(
                asset: extra,
                rank: 3,
                price: 1.5,
                change24hPercent: 0.0,
                change24hAbsolute: 0.0,
              ),
            ],
            nextOffset: 22,
            hasMore: true,
          ),
        );
      },
      build: buildBloc,
      seed: () => const MarketsState(
        status: MarketsStatus.success,
        quotes: _seed,
        pageOffset: 2,
        hasMore: true,
      ),
      act: (MarketsBloc bloc) =>
          bloc.add(const MarketsNextPageRequested()),
      verify: (MarketsBloc bloc) {
        expect(bloc.state.quotes, hasLength(3));
        expect(bloc.state.quotes.last.asset.symbol, 'NOVA');
        expect(bloc.state.pageOffset, 22);
        expect(bloc.state.isLoadingMore, isFalse);
      },
    );

    blocTest<MarketsBloc, MarketsState>(
      'MarketsNextPageRequested is a no-op when hasMore is false',
      build: buildBloc,
      seed: () => const MarketsState(
        status: MarketsStatus.success,
        quotes: _seed,
        pageOffset: 9,
        hasMore: false,
      ),
      act: (MarketsBloc bloc) =>
          bloc.add(const MarketsNextPageRequested()),
      expect: () => <MarketsState>[],
      verify: (_) {
        verifyNever(
          () => repository.getMarketQuotesPage(
            offset: any(named: 'offset'),
            limit: any(named: 'limit'),
          ),
        );
      },
    );
  });
}
