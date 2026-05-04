import 'package:equatable/equatable.dart';

/// One OHLC bucket of price + volume activity.
///
/// `isGap` slots are "data unavailable" placeholders inserted around paused
/// stream periods. They have no real OHLC data and should be drawn as red
/// rectangles, ignored by aggregation, lerp, hit-testing, etc.
class Candle extends Equatable {
  const Candle({
    required this.timestamp,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
    this.isGap = false,
  });

  /// Convenience constructor for a "data unavailable" slot.
  const Candle.gap({required this.timestamp})
    : open = 0,
      high = 0,
      low = 0,
      close = 0,
      volume = 0,
      isGap = true;

  final DateTime timestamp;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;
  final bool isGap;

  bool get isBullish => close >= open;

  Candle copyWith({
    DateTime? timestamp,
    double? open,
    double? high,
    double? low,
    double? close,
    double? volume,
    bool? isGap,
  }) {
    return Candle(
      timestamp: timestamp ?? this.timestamp,
      open: open ?? this.open,
      high: high ?? this.high,
      low: low ?? this.low,
      close: close ?? this.close,
      volume: volume ?? this.volume,
      isGap: isGap ?? this.isGap,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    timestamp,
    open,
    high,
    low,
    close,
    volume,
    isGap,
  ];
}
