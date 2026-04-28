import 'package:equatable/equatable.dart';

import 'price_point.dart';

/// High-level account balance shown on the Home dashboard.
class BalanceSummary extends Equatable {
  const BalanceSummary({
    required this.totalBalanceUsd,
    required this.change24hUsd,
    required this.change24hPercent,
    required this.sparkline,
  });

  final double totalBalanceUsd;
  final double change24hUsd;
  final double change24hPercent;
  final List<PricePoint> sparkline;

  bool get isPositive => change24hPercent >= 0;

  @override
  List<Object?> get props => <Object?>[
    totalBalanceUsd,
    change24hUsd,
    change24hPercent,
    sparkline,
  ];
}
