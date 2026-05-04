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
    this.pageOffset = 0,
    this.hasMore = true,
    this.isLoadingMore = false,
  });

  final MarketsStatus status;
  final List<CryptoQuote> quotes;
  final AssetCategory category;
  final String query;
  final String? errorMessage;

  /// Cursor for the next page of paginated quotes. Equal to
  /// `quotes.length` when no filtering or duplicate suppression has
  /// pruned the loaded set, but tracked separately so the cursor
  /// stays aligned with the underlying API regardless of UI-side
  /// filtering.
  final int pageOffset;

  /// Whether the API has more pages to serve. The mock returns
  /// `true` indefinitely (the catalog is generated on demand); a
  /// real backend would flip it to `false` once exhausted.
  final bool hasMore;

  /// True while a `MarketsNextPageRequested` is in flight.
  /// Suppresses duplicate triggers from rapid scroll events and
  /// drives the trailing loading indicator on the markets list.
  final bool isLoadingMore;

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
    int? pageOffset,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return MarketsState(
      status: status ?? this.status,
      quotes: quotes ?? this.quotes,
      category: category ?? this.category,
      query: query ?? this.query,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      pageOffset: pageOffset ?? this.pageOffset,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    status,
    quotes,
    category,
    query,
    errorMessage,
    pageOffset,
    hasMore,
    isLoadingMore,
  ];
}
