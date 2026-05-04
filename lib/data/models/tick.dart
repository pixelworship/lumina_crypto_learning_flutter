import 'package:equatable/equatable.dart';

enum TickSide { buy, sell }

/// A single trade tick on the live price feed.
class Tick extends Equatable {
  const Tick({
    required this.price,
    required this.side,
    required this.volume,
    required this.timestamp,
  });

  final double price;
  final TickSide side;
  final double volume;
  final DateTime timestamp;

  @override
  List<Object?> get props => <Object?>[price, side, volume, timestamp];
}
