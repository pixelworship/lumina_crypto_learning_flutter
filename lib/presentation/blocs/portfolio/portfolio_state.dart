import 'package:equatable/equatable.dart';

import '../../../data/models/portfolio_holding.dart';

enum PortfolioStatus { initial, loading, success, failure }

class PortfolioState extends Equatable {
  const PortfolioState({
    this.status = PortfolioStatus.initial,
    this.summary,
    this.errorMessage,
  });

  final PortfolioStatus status;
  final PortfolioSummary? summary;
  final String? errorMessage;

  PortfolioState copyWith({
    PortfolioStatus? status,
    PortfolioSummary? summary,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PortfolioState(
      status: status ?? this.status,
      summary: summary ?? this.summary,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => <Object?>[status, summary, errorMessage];
}
