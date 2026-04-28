import 'package:equatable/equatable.dart';

abstract class PortfolioEvent extends Equatable {
  const PortfolioEvent();

  @override
  List<Object?> get props => <Object?>[];
}

class PortfolioRequested extends PortfolioEvent {
  const PortfolioRequested();
}

class PortfolioRefreshed extends PortfolioEvent {
  const PortfolioRefreshed();
}
