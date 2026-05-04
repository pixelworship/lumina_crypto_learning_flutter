import 'package:equatable/equatable.dart';

import '../../../data/models/asset_category.dart';

abstract class MarketsEvent extends Equatable {
  const MarketsEvent();

  @override
  List<Object?> get props => <Object?>[];
}

/// Initial load of market quotes.
class MarketsRequested extends MarketsEvent {
  const MarketsRequested();
}

/// Pull-to-refresh — drops the loaded pages and re-fetches page 0.
class MarketsRefreshed extends MarketsEvent {
  const MarketsRefreshed();
}

/// Fired when the markets list scrolls within the prefetch threshold
/// of its bottom edge. The bloc fetches the next page of quotes and
/// appends them; the screen renders a trailing loading indicator
/// while in flight.
class MarketsNextPageRequested extends MarketsEvent {
  const MarketsNextPageRequested();
}

class MarketsCategoryChanged extends MarketsEvent {
  const MarketsCategoryChanged(this.category);

  final AssetCategory category;

  @override
  List<Object?> get props => <Object?>[category];
}

class MarketsSearchChanged extends MarketsEvent {
  const MarketsSearchChanged(this.query);

  final String query;

  @override
  List<Object?> get props => <Object?>[query];
}
