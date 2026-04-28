import 'package:equatable/equatable.dart';

import 'crypto_asset.dart';
import 'order_book_entry.dart';
import 'price_point.dart';

/// Time ranges supported by the Trade screen chart.
enum ChartRange {
  oneHour('1H', Duration(hours: 1)),
  oneDay('1D', Duration(days: 1)),
  oneWeek('1W', Duration(days: 7)),
  oneMonth('1M', Duration(days: 30)),
  oneYear('1Y', Duration(days: 365));

  const ChartRange(this.label, this.window);

  final String label;
  final Duration window;
}

/// Everything the Trade screen needs for a single base/quote pair.
class TradePairSnapshot extends Equatable {
  const TradePairSnapshot({
    required this.base,
    required this.quote,
    required this.price,
    required this.changePercent,
    required this.range,
    required this.priceHistory,
    required this.bids,
    required this.asks,
  });

  final CryptoAsset base;
  final CryptoAsset quote;
  final double price;
  final double changePercent;
  final ChartRange range;
  final List<PricePoint> priceHistory;
  final List<OrderBookEntry> bids;
  final List<OrderBookEntry> asks;

  String get pairLabel => '${base.symbol} / ${quote.symbol}';
  bool get isPositive => changePercent >= 0;

  @override
  List<Object?> get props => <Object?>[
    base,
    quote,
    price,
    changePercent,
    range,
    priceHistory,
    bids,
    asks,
  ];
}
