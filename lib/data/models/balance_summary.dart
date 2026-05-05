import 'package:equatable/equatable.dart';

import 'price_point.dart';

/// High-level account balance shown on the Home dashboard.
///
/// `valueAt24hAgo` is the historical anchor used by [HomeBloc] to
/// recompute [change24hPercent] / [change24hUsd] locally on every
/// live price tick. The warehouse API computes this once per fetch
/// (against the same noise curve that powers the chart and markets);
/// live blocs reuse the cached value across ticks so no consumer ever
/// reads historical data outside the API surface.
class BalanceSummary extends Equatable {
  const BalanceSummary({
    required this.totalBalanceUsd,
    required this.change24hUsd,
    required this.change24hPercent,
    required this.valueAt24hAgo,
    required this.sparkline,
  });

  final double totalBalanceUsd;
  final double change24hUsd;
  final double change24hPercent;

  /// Aggregate portfolio value 24 hours before this summary was
  /// computed.
  final double valueAt24hAgo;

  final List<PricePoint> sparkline;

  bool get isPositive => change24hPercent >= 0;

  @override
  List<Object?> get props => <Object?>[
    totalBalanceUsd,
    change24hUsd,
    change24hPercent,
    valueAt24hAgo,
    sparkline,
  ];
}
