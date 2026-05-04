import 'package:equatable/equatable.dart';

import '../../../data/models/candle.dart';
import '../../../data/models/market_event.dart';
import '../../../data/models/timeframe.dart';

/// Snapshot of everything the chart UI needs to render a frame.
class ChartState extends Equatable {
  const ChartState({
    required this.symbol,
    required this.timeframe,
    required this.candles,
    required this.events,
    required this.isStreaming,
    required this.isPaused,
    required this.tickSpeed,
    required this.priceOffset,
    required this.glowEnabled,
    required this.autoScaleEnabled,
    required this.volumeOverlayEnabled,
    required this.isBackfilling,
    required this.isExtendingHistory,
    required this.isLoadingHistory,
    this.lastPrice,
    this.pauseStartedAt,
  });

  factory ChartState.initial({String symbol = 'BTC'}) => ChartState(
    symbol: symbol,
    timeframe: Timeframe.m1,
    candles: const <Candle>[],
    events: const <MarketEvent>[],
    isStreaming: false,
    isPaused: false,
    tickSpeed: 1.0,
    priceOffset: 0.0,
    glowEnabled: true,
    autoScaleEnabled: true,
    volumeOverlayEnabled: false,
    isBackfilling: false,
    isExtendingHistory: false,
    isLoadingHistory: false,
    lastPrice: null,
    pauseStartedAt: null,
  );

  /// The asset symbol whose ticks this chart is currently streaming
  /// (e.g. `BTC`, `ETH`). Driven by `ChartSymbolChanged` so tapping a
  /// different asset row updates the candlestick data without
  /// recreating the bloc.
  final String symbol;

  final Timeframe timeframe;
  final List<Candle> candles;

  /// Discrete real-world events (earnings, news, tweets, ...) overlaid on
  /// the timeline. Sorted ascending by `MarketEvent.timestamp`.
  final List<MarketEvent> events;
  final bool isStreaming;

  /// True while the live tick subscription is paused (debug "wifi out").
  final bool isPaused;

  /// When [isPaused] is true, the wall-clock time at which the pause
  /// began. Used to size the "DATA UNAVAILABLE" gap the chart scrolls
  /// into.
  final DateTime? pauseStartedAt;

  /// Multiplier on the mock data emission frequency. 1.0 == default.
  final double tickSpeed;

  /// Constant offset (in price units) added on top of the underlying
  /// price source. Useful for debug-driven price shocks.
  final double priceOffset;

  /// Whether candle glow is rendered. Owned by the BLoC so renderers stay
  /// pure presentational components.
  final bool glowEnabled;

  /// When true, the chart's vertical price range tracks the visible
  /// candles each frame so newly arriving high/low ticks always fit.
  /// When false, the range is frozen at whatever it was when auto-scale
  /// was disabled and ticks outside that band are simply clipped.
  final bool autoScaleEnabled;

  /// When true, a translucent purple line+gradient area chart of
  /// per-candle volume is drawn behind the candles, spanning the full
  /// plot area. Off by default; toggled from the debug panel.
  final bool volumeOverlayEnabled;

  /// True while the bloc is fetching mock ticks to backfill gap slots.
  final bool isBackfilling;

  /// True while the bloc is fetching an additional slice of older ticks
  /// to extend (double) the visible history backward.
  final bool isExtendingHistory;

  /// True while the bloc is loading the initial history for the
  /// active [symbol] (or a fresh history after a symbol switch).
  /// Drives the chart's loading-overlay UX: an empty `candles` list
  /// shows a full-screen indicator, a non-empty list (cache hit)
  /// shows the cached chart with a small overlay badge.
  final bool isLoadingHistory;

  final double? lastPrice;

  ChartState copyWith({
    String? symbol,
    Timeframe? timeframe,
    List<Candle>? candles,
    List<MarketEvent>? events,
    bool? isStreaming,
    bool? isPaused,
    double? tickSpeed,
    double? priceOffset,
    bool? glowEnabled,
    bool? autoScaleEnabled,
    bool? volumeOverlayEnabled,
    bool? isBackfilling,
    bool? isExtendingHistory,
    bool? isLoadingHistory,
    double? lastPrice,
    DateTime? pauseStartedAt,
    bool clearPauseStartedAt = false,
    bool clearLastPrice = false,
  }) {
    return ChartState(
      symbol: symbol ?? this.symbol,
      timeframe: timeframe ?? this.timeframe,
      candles: candles ?? this.candles,
      events: events ?? this.events,
      isStreaming: isStreaming ?? this.isStreaming,
      isPaused: isPaused ?? this.isPaused,
      tickSpeed: tickSpeed ?? this.tickSpeed,
      priceOffset: priceOffset ?? this.priceOffset,
      glowEnabled: glowEnabled ?? this.glowEnabled,
      autoScaleEnabled: autoScaleEnabled ?? this.autoScaleEnabled,
      volumeOverlayEnabled:
          volumeOverlayEnabled ?? this.volumeOverlayEnabled,
      isBackfilling: isBackfilling ?? this.isBackfilling,
      isExtendingHistory: isExtendingHistory ?? this.isExtendingHistory,
      isLoadingHistory: isLoadingHistory ?? this.isLoadingHistory,
      lastPrice: clearLastPrice ? null : (lastPrice ?? this.lastPrice),
      pauseStartedAt: clearPauseStartedAt
          ? null
          : (pauseStartedAt ?? this.pauseStartedAt),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    symbol,
    timeframe,
    candles,
    events,
    isStreaming,
    isPaused,
    tickSpeed,
    priceOffset,
    glowEnabled,
    autoScaleEnabled,
    volumeOverlayEnabled,
    isBackfilling,
    isExtendingHistory,
    isLoadingHistory,
    lastPrice,
    pauseStartedAt,
  ];
}
