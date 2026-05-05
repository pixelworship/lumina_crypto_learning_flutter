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
///
/// `priceAt24hAgo` is the historical anchor returned by the warehouse
/// API; consumers (the markets bloc, the home watchlist) cache it
/// and recompute [change24hPercent] locally on every live price tick
/// instead of re-querying historical data — that way, all historical
/// reads still flow through the API surface (and only the API surface
/// touches the noise generator).
class CryptoQuote extends Equatable {
  const CryptoQuote({
    required this.asset,
    required this.rank,
    required this.price,
    required this.change24hPercent,
    required this.change24hAbsolute,
    required this.priceAt24hAgo,
  });

  final CryptoAsset asset;
  final int rank;
  final double price;
  final double change24hPercent;
  final double change24hAbsolute;

  /// Anchor price 24 hours before this quote was issued. The
  /// warehouse API computes this once per request; live blocs reuse
  /// it across ticks until the next refresh fetches a fresh anchor.
  final double priceAt24hAgo;

  bool get isPositive => change24hPercent >= 0;

  CryptoQuote copyWith({
    double? price,
    double? change24hPercent,
    double? change24hAbsolute,
    double? priceAt24hAgo,
  }) {
    return CryptoQuote(
      asset: asset,
      rank: rank,
      price: price ?? this.price,
      change24hPercent: change24hPercent ?? this.change24hPercent,
      change24hAbsolute: change24hAbsolute ?? this.change24hAbsolute,
      priceAt24hAgo: priceAt24hAgo ?? this.priceAt24hAgo,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    asset,
    rank,
    price,
    change24hPercent,
    change24hAbsolute,
    priceAt24hAgo,
  ];
}
