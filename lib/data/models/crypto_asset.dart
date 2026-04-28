import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

import 'asset_category.dart';

/// Static, brand-level information about a tradable crypto asset.
class CryptoAsset extends Equatable {
  const CryptoAsset({
    required this.id,
    required this.symbol,
    required this.name,
    required this.color,
    required this.iconLetter,
    required this.categories,
  });

  final String id;
  final String symbol;
  final String name;
  final Color color;
  final String iconLetter;
  final List<AssetCategory> categories;

  @override
  List<Object?> get props =>
      <Object?>[id, symbol, name, color, iconLetter, categories];
}

/// A real-time market quote for a [CryptoAsset].
class CryptoQuote extends Equatable {
  const CryptoQuote({
    required this.asset,
    required this.rank,
    required this.price,
    required this.change24hPercent,
    required this.change24hAbsolute,
  });

  final CryptoAsset asset;
  final int rank;
  final double price;
  final double change24hPercent;
  final double change24hAbsolute;

  bool get isPositive => change24hPercent >= 0;

  CryptoQuote copyWith({
    double? price,
    double? change24hPercent,
    double? change24hAbsolute,
  }) {
    return CryptoQuote(
      asset: asset,
      rank: rank,
      price: price ?? this.price,
      change24hPercent: change24hPercent ?? this.change24hPercent,
      change24hAbsolute: change24hAbsolute ?? this.change24hAbsolute,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    asset,
    rank,
    price,
    change24hPercent,
    change24hAbsolute,
  ];
}
