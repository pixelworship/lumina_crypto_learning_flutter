import 'package:flutter_demo/data/models/balance_summary.dart';
import 'package:flutter_demo/data/models/portfolio_holding.dart';
import 'package:flutter_demo/data/repositories/portfolio_repository.dart';
import 'package:flutter_demo/data/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../fixtures/test_assets.dart';

class _MockApiService extends Mock implements ApiService {}

void main() {
  late _MockApiService api;
  late PortfolioRepository repository;

  setUp(() {
    api = _MockApiService();
    repository = MockPortfolioRepository(api);
  });

  group('MockPortfolioRepository.getBalanceSummary', () {
    test('delegates to ApiService.fetchBalanceSummary', () async {
      when(api.fetchBalanceSummary).thenAnswer((_) async => TestAssets.balance);

      final BalanceSummary result = await repository.getBalanceSummary();

      expect(result, TestAssets.balance);
      verify(api.fetchBalanceSummary).called(1);
      verifyNoMoreInteractions(api);
    });

    test('propagates errors from the API service', () async {
      when(api.fetchBalanceSummary).thenThrow(Exception('boom'));

      expect(repository.getBalanceSummary, throwsException);
    });
  });

  group('MockPortfolioRepository.getPortfolio', () {
    test('delegates to ApiService.fetchPortfolio', () async {
      when(api.fetchPortfolio).thenAnswer((_) async => TestAssets.portfolio);

      final PortfolioSummary result = await repository.getPortfolio();

      expect(result, TestAssets.portfolio);
      verify(api.fetchPortfolio).called(1);
      verifyNoMoreInteractions(api);
    });
  });

  group('MockPortfolioRepository.deposit', () {
    test('forwards the amount and returns the API result', () async {
      when(
        () => api.submitDeposit(amountUsd: any(named: 'amountUsd')),
      ).thenAnswer((_) async => true);

      final bool ok = await repository.deposit(125.50);

      expect(ok, isTrue);
      verify(() => api.submitDeposit(amountUsd: 125.50)).called(1);
      verifyNoMoreInteractions(api);
    });

    test('passes negative amounts through verbatim (no client validation)', () async {
      when(
        () => api.submitDeposit(amountUsd: any(named: 'amountUsd')),
      ).thenAnswer((_) async => false);

      final bool ok = await repository.deposit(-1);

      expect(ok, isFalse);
      verify(() => api.submitDeposit(amountUsd: -1)).called(1);
    });
  });

  group('MockPortfolioRepository.withdraw', () {
    test('forwards the amount and returns the API result', () async {
      when(
        () => api.submitWithdrawal(amountUsd: any(named: 'amountUsd')),
      ).thenAnswer((_) async => true);

      final bool ok = await repository.withdraw(40.0);

      expect(ok, isTrue);
      verify(() => api.submitWithdrawal(amountUsd: 40.0)).called(1);
      verifyNoMoreInteractions(api);
    });
  });
}
