import 'package:equatable/equatable.dart';

/// A single point on a price-over-time chart.
class PricePoint extends Equatable {
  const PricePoint({required this.timestamp, required this.price});

  final DateTime timestamp;
  final double price;

  @override
  List<Object?> get props => <Object?>[timestamp, price];
}
