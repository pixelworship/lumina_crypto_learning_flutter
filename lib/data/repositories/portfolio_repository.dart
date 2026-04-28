import '../models/balance_summary.dart';
import '../models/portfolio_holding.dart';
import '../services/api_service.dart';

/// Repository abstraction over balances, holdings, and money movement.
abstract class PortfolioRepository {
  Future<BalanceSummary> getBalanceSummary();
  Future<PortfolioSummary> getPortfolio();
  Future<bool> deposit(double amountUsd);
  Future<bool> withdraw(double amountUsd);
}

class MockPortfolioRepository implements PortfolioRepository {
  MockPortfolioRepository(this._api);

  final ApiService _api;

  @override
  Future<BalanceSummary> getBalanceSummary() => _api.fetchBalanceSummary();

  @override
  Future<PortfolioSummary> getPortfolio() => _api.fetchPortfolio();

  @override
  Future<bool> deposit(double amountUsd) =>
      _api.submitDeposit(amountUsd: amountUsd);

  @override
  Future<bool> withdraw(double amountUsd) =>
      _api.submitWithdrawal(amountUsd: amountUsd);
}
