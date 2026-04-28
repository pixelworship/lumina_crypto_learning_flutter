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

/// Pull-to-refresh.
class MarketsRefreshed extends MarketsEvent {
  const MarketsRefreshed();
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
