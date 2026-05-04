import 'package:equatable/equatable.dart';

/// A resolved period during which the live tick stream was paused.
///
/// Used to re-insert "DATA UNAVAILABLE" slots when the candle list is
/// rebuilt (e.g. on timeframe change).
class PauseGap extends Equatable {
  const PauseGap({required this.start, required this.end});

  final DateTime start;
  final DateTime end;

  Duration get duration => end.difference(start);

  @override
  List<Object?> get props => <Object?>[start, end];
}
