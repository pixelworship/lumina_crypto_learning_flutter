import 'package:equatable/equatable.dart';

enum OrderSide { bid, ask }

/// Single line in an order book - either a bid or an ask.
class OrderBookEntry extends Equatable {
  const OrderBookEntry({
    required this.price,
    required this.amount,
    required this.side,
  });

  final double price;
  final double amount;
  final OrderSide side;

  double get total => price * amount;

  @override
  List<Object?> get props => <Object?>[price, amount, side];
}
