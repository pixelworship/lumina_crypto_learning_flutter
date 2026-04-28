import 'package:equatable/equatable.dart';

abstract class HomeEvent extends Equatable {
  const HomeEvent();

  @override
  List<Object?> get props => <Object?>[];
}

class HomeRequested extends HomeEvent {
  const HomeRequested();
}

class HomeRefreshed extends HomeEvent {
  const HomeRefreshed();
}

/// Quick action triggered from the dashboard.
class HomeQuickActionTriggered extends HomeEvent {
  const HomeQuickActionTriggered(this.action);

  final HomeQuickAction action;

  @override
  List<Object?> get props => <Object?>[action];
}

enum HomeQuickAction { deposit, withdraw, swap }
