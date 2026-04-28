import 'package:equatable/equatable.dart';

import 'crypto_asset.dart';

/// A single asset position in the user's portfolio.
class PortfolioHolding extends Equatable {
  const PortfolioHolding({
    required this.asset,
    required this.quantity,
    required this.currentPrice,
    required this.costBasisPerUnit,
    required this.allocationPercent,
  });

  final CryptoAsset asset;
  final double quantity;
  final double currentPrice;
  final double costBasisPerUnit;
  final double allocationPercent;

  double get marketValue => quantity * currentPrice;
  double get costBasis => quantity * costBasisPerUnit;
  double get unrealizedGainUsd => marketValue - costBasis;
  double get unrealizedGainPercent =>
      costBasis == 0 ? 0 : (unrealizedGainUsd / costBasis) * 100;
  bool get isPositive => unrealizedGainUsd >= 0;

  @override
  List<Object?> get props => <Object?>[
    asset,
    quantity,
    currentPrice,
    costBasisPerUnit,
    allocationPercent,
  ];
}

/// Aggregated portfolio metrics shown at the top of the Portfolio screen.
class PortfolioSummary extends Equatable {
  const PortfolioSummary({
    required this.totalValueUsd,
    required this.changeTodayUsd,
    required this.changeTodayPercent,
    required this.holdings,
  });

  final double totalValueUsd;
  final double changeTodayUsd;
  final double changeTodayPercent;
  final List<PortfolioHolding> holdings;

  int get assetCount => holdings.length;
  bool get isPositive => changeTodayUsd >= 0;

  @override
  List<Object?> get props => <Object?>[
    totalValueUsd,
    changeTodayUsd,
    changeTodayPercent,
    holdings,
  ];
}
