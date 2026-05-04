import 'package:equatable/equatable.dart';

import '../../../data/models/timeframe.dart';

/// Public events accepted by `ChartBloc`. Two private events
/// (`_TickReceived`, `_MarketEventTimerTicked`) live alongside the bloc
/// itself in `chart_bloc.dart`.
abstract class ChartEvent extends Equatable {
  const ChartEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

class ChartStarted extends ChartEvent {
  const ChartStarted({this.symbol});

  /// Optional initial symbol. When null, the bloc keeps whatever the
  /// initial state had (default `BTC`). Useful when the active symbol
  /// is known at start (e.g. routing into the asset detail screen).
  final String? symbol;

  @override
  List<Object?> get props => <Object?>[symbol];
}

class ChartStopped extends ChartEvent {
  const ChartStopped();
}

/// Switches the chart to a new asset. The bloc clears candles, events,
/// and gap history, then re-fetches history and re-subscribes to live
/// ticks scoped to the new symbol.
class ChartSymbolChanged extends ChartEvent {
  const ChartSymbolChanged(this.symbol);

  final String symbol;

  @override
  List<Object?> get props => <Object?>[symbol];
}

class TimeframeChanged extends ChartEvent {
  const TimeframeChanged(this.timeframe);

  final Timeframe timeframe;

  @override
  List<Object?> get props => <Object?>[timeframe];
}

class TickSpeedChanged extends ChartEvent {
  const TickSpeedChanged(this.multiplier);

  final double multiplier;

  @override
  List<Object?> get props => <Object?>[multiplier];
}

class PriceOffsetChanged extends ChartEvent {
  const PriceOffsetChanged(this.offset);

  final double offset;

  @override
  List<Object?> get props => <Object?>[offset];
}

class GlowToggled extends ChartEvent {
  const GlowToggled();
}

class AutoScaleToggled extends ChartEvent {
  const AutoScaleToggled();
}

class VolumeOverlayToggled extends ChartEvent {
  const VolumeOverlayToggled();
}

class PauseToggled extends ChartEvent {
  const PauseToggled();
}

/// Asks the bloc to fetch mock ticks covering every resolved pause gap and
/// merge them back into history, removing the "DATA UNAVAILABLE" slots.
class BackfillRequested extends ChartEvent {
  const BackfillRequested();
}

/// Asks the bloc to fetch an additional slice of older history equal in
/// span to whatever is currently loaded, doubling the available backlog.
class HistoryExtendRequested extends ChartEvent {
  const HistoryExtendRequested();
}

/// Asks the bloc to spawn a randomly-picked `MarketEvent` at "now". Wired
/// to both the periodic timer and the debug-drop FAB.
class MarketEventSpawnRequested extends ChartEvent {
  const MarketEventSpawnRequested();
}
