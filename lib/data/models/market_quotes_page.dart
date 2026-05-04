import 'package:equatable/equatable.dart';

import 'crypto_asset.dart';

/// One page of paginated market quotes.
///
/// Modeled after a typical paginated REST response — the caller asks
/// for `[offset, offset + limit)` and gets back the slice plus a
/// cursor (`nextOffset`) and a `hasMore` flag so it knows whether to
/// keep paging.
class MarketQuotesPage extends Equatable {
  const MarketQuotesPage({
    required this.quotes,
    required this.nextOffset,
    required this.hasMore,
  });

  /// The quotes for this page, ordered by ascending rank.
  final List<CryptoQuote> quotes;

  /// Offset to pass on the next [fetchMarketQuotesPage] call to
  /// continue paging where this page left off.
  final int nextOffset;

  /// Whether further pages exist beyond [nextOffset]. The mock API
  /// returns `true` indefinitely; real backends will eventually flip
  /// it to `false` once the catalog is exhausted.
  final bool hasMore;

  @override
  List<Object?> get props => <Object?>[quotes, nextOffset, hasMore];
}
