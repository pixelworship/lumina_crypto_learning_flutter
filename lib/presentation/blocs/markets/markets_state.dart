import 'package:equatable/equatable.dart';

import '../../../data/models/asset_category.dart';
import '../../../data/models/crypto_asset.dart';

enum MarketsStatus { initial, loading, success, failure }

class MarketsState extends Equatable {
  const MarketsState({
    this.status = MarketsStatus.initial,
    this.quotes = const <CryptoQuote>[],
    this.category = AssetCategory.all,
    this.query = '',
    this.errorMessage,
  });

  final MarketsStatus status;
  final List<CryptoQuote> quotes;
  final AssetCategory category;
  final String query;
  final String? errorMessage;

  /// Quotes filtered by the active category and search query.
  List<CryptoQuote> get visibleQuotes {
    final String normalized = query.trim().toLowerCase();
    return quotes.where((CryptoQuote quote) {
      final bool inCategory =
          category == AssetCategory.all ||
          quote.asset.categories.contains(category);
      if (!inCategory) return false;
      if (normalized.isEmpty) return true;
      return quote.asset.name.toLowerCase().contains(normalized) ||
          quote.asset.symbol.toLowerCase().contains(normalized);
    }).toList();
  }

  MarketsState copyWith({
    MarketsStatus? status,
    List<CryptoQuote>? quotes,
    AssetCategory? category,
    String? query,
    String? errorMessage,
    bool clearError = false,
  }) {
    return MarketsState(
      status: status ?? this.status,
      quotes: quotes ?? this.quotes,
      category: category ?? this.category,
      query: query ?? this.query,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    status,
    quotes,
    category,
    query,
    errorMessage,
  ];
}
