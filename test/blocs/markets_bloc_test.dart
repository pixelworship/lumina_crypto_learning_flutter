import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_demo/data/models/asset_category.dart';
import 'package:flutter_demo/data/models/crypto_asset.dart';
import 'package:flutter_demo/data/repositories/market_repository.dart';
import 'package:flutter_demo/presentation/blocs/markets/markets_bloc.dart';
import 'package:flutter_demo/presentation/blocs/markets/markets_event.dart';
import 'package:flutter_demo/presentation/blocs/markets/markets_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _FakeMarketRepository extends Mock implements MarketRepository {}

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

  setUp(() {
    repository = _FakeMarketRepository();
    when(repository.getMarketQuotes).thenAnswer((_) async => _seed);
  });

  group('MarketsBloc', () {
    blocTest<MarketsBloc, MarketsState>(
      'loads quotes on MarketsRequested',
      build: () => MarketsBloc(marketRepository: repository),
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
      build: () => MarketsBloc(marketRepository: repository),
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
      build: () => MarketsBloc(marketRepository: repository),
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
      setUp: () => when(repository.getMarketQuotes)
          .thenThrow(Exception('boom')),
      build: () => MarketsBloc(marketRepository: repository),
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
  });
}
