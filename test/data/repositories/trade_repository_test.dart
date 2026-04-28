import 'package:flutter_demo/data/models/trade_pair_snapshot.dart';
import 'package:flutter_demo/data/repositories/trade_repository.dart';
import 'package:flutter_demo/data/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../fixtures/test_assets.dart';

class _MockApiService extends Mock implements ApiService {}

void main() {
  setUpAll(() {
    registerFallbackValue(ChartRange.oneDay);
  });

  late _MockApiService api;
  late TradeRepository repository;

  setUp(() {
    api = _MockApiService();
    repository = MockTradeRepository(api);
  });

  group('MockTradeRepository.getPair', () {
    test('forwards all arguments to ApiService.fetchTradePair', () async {
      when(
        () => api.fetchTradePair(
          baseSymbol: any(named: 'baseSymbol'),
          quoteSymbol: any(named: 'quoteSymbol'),
          range: any(named: 'range'),
        ),
      ).thenAnswer((_) async => TestAssets.tradePair);

      final TradePairSnapshot result = await repository.getPair(
        baseSymbol: 'BTC',
        quoteSymbol: 'USDT',
        range: ChartRange.oneWeek,
      );

      expect(result, TestAssets.tradePair);
      verify(
        () => api.fetchTradePair(
          baseSymbol: 'BTC',
          quoteSymbol: 'USDT',
          range: ChartRange.oneWeek,
        ),
      ).called(1);
      verifyNoMoreInteractions(api);
    });

    test('propagates errors from the API service', () async {
      when(
        () => api.fetchTradePair(
          baseSymbol: any(named: 'baseSymbol'),
          quoteSymbol: any(named: 'quoteSymbol'),
          range: any(named: 'range'),
        ),
      ).thenThrow(ArgumentError.value('XYZ'));

      expect(
        () => repository.getPair(
          baseSymbol: 'XYZ',
          quoteSymbol: 'USDT',
          range: ChartRange.oneDay,
        ),
        throwsArgumentError,
      );
    });
  });

  group('MockTradeRepository.swap', () {
    test('forwards all arguments and returns the API result', () async {
      when(
        () => api.submitSwap(
          fromSymbol: any(named: 'fromSymbol'),
          toSymbol: any(named: 'toSymbol'),
          amount: any(named: 'amount'),
        ),
      ).thenAnswer((_) async => true);

      final bool ok = await repository.swap(
        fromSymbol: 'BTC',
        toSymbol: 'USDT',
        amount: 0.25,
      );

      expect(ok, isTrue);
      verify(
        () => api.submitSwap(
          fromSymbol: 'BTC',
          toSymbol: 'USDT',
          amount: 0.25,
        ),
      ).called(1);
      verifyNoMoreInteractions(api);
    });

    test('returns false when the API rejects the swap', () async {
      when(
        () => api.submitSwap(
          fromSymbol: any(named: 'fromSymbol'),
          toSymbol: any(named: 'toSymbol'),
          amount: any(named: 'amount'),
        ),
      ).thenAnswer((_) async => false);

      final bool ok = await repository.swap(
        fromSymbol: 'BTC',
        toSymbol: 'USDT',
        amount: 0.25,
      );

      expect(ok, isFalse);
    });
  });
}
