import 'package:flutter_demo/data/models/crypto_asset.dart';
import 'package:flutter_demo/data/models/market_quotes_page.dart';
import 'package:flutter_demo/data/repositories/market_repository.dart';
import 'package:flutter_demo/data/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../fixtures/test_assets.dart';

class _MockApiService extends Mock implements ApiService {}

void main() {
  late _MockApiService api;
  late MarketRepository repository;

  setUp(() {
    api = _MockApiService();
    repository = MockMarketRepository(api);
  });

  group('MockMarketRepository.getMarketQuotes', () {
    test('delegates to ApiService.fetchMarketQuotes', () async {
      const List<CryptoQuote> stub = <CryptoQuote>[
        TestAssets.btcQuote,
        TestAssets.ethQuote,
      ];
      when(api.fetchMarketQuotes).thenAnswer((_) async => stub);

      final List<CryptoQuote> result = await repository.getMarketQuotes();

      expect(result, stub);
      verify(api.fetchMarketQuotes).called(1);
      verifyNoMoreInteractions(api);
    });

    test('propagates errors from the API service', () async {
      when(api.fetchMarketQuotes).thenThrow(Exception('network down'));

      expect(repository.getMarketQuotes, throwsException);
    });
  });

  group('MockMarketRepository.getWatchlist', () {
    test('delegates to ApiService.fetchWatchlist', () async {
      when(api.fetchWatchlist).thenAnswer((_) async => TestAssets.watchlist);

      final List<CryptoQuote> result = await repository.getWatchlist();

      expect(result, TestAssets.watchlist);
      verify(api.fetchWatchlist).called(1);
      verifyNoMoreInteractions(api);
    });

    test('propagates errors from the API service', () async {
      when(api.fetchWatchlist).thenThrow(StateError('boom'));

      expect(repository.getWatchlist, throwsStateError);
    });
  });

  test('the two methods are independent and do not call each other', () async {
    when(api.fetchMarketQuotes).thenAnswer((_) async => <CryptoQuote>[]);
    when(api.fetchWatchlist).thenAnswer((_) async => <CryptoQuote>[]);

    await repository.getMarketQuotes();
    verify(api.fetchMarketQuotes).called(1);
    verifyNever(api.fetchWatchlist);

    await repository.getWatchlist();
    verify(api.fetchWatchlist).called(1);
  });

  group('MockMarketRepository.getMarketQuotesPage', () {
    test('forwards offset and limit to ApiService.fetchMarketQuotesPage',
        () async {
      const MarketQuotesPage page = MarketQuotesPage(
        quotes: <CryptoQuote>[TestAssets.btcQuote],
        nextOffset: 20,
        hasMore: true,
      );
      when(
        () => api.fetchMarketQuotesPage(
          offset: any(named: 'offset'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((_) async => page);

      final MarketQuotesPage result =
          await repository.getMarketQuotesPage(offset: 0, limit: 20);

      expect(result, page);
      verify(() => api.fetchMarketQuotesPage(offset: 0, limit: 20)).called(1);
    });
  });
}
