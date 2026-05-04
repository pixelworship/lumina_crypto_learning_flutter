import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/candle.dart';
import '../../../data/models/fill.dart';
import '../../../data/models/market_event.dart';
import '../../../data/models/timeframe.dart';
import '../../../design_system/lumina_ui.dart';
import '../../blocs/chart/chart_bloc.dart';
import '../../blocs/chart/chart_event.dart';
import 'animated_candles.dart';
import 'animated_volume_overlay.dart';
import 'event_marker_overlay.dart';
import 'fill_marker_overlay.dart';
import 'ohlc_tooltip.dart';
import 'painters/candle_painter.dart';
import 'painters/chart_axes_painter.dart';
import 'painters/crosshair_painter.dart';
import 'painters/missing_data_painter.dart';

/// Renders the candlestick chart inside its plot area. Owns:
///   * the visible window (pan + pinch zoom + scroll-wheel zoom),
///   * the long-press crosshair + OHLC tooltip,
///   * the auto-follow / LIVE pill behavior,
///   * the live-pause "data unavailable" stripe.
///
/// All theme-derived colors come from `context.tokens` and are passed
/// through to the painters.
class ChartRenderer extends StatelessWidget {
  const ChartRenderer({
    super.key,
    required this.candles,
    required this.timeframe,
    required this.events,
    required this.fills,
    this.glowEnabled = true,
    this.autoScaleEnabled = true,
    this.volumeOverlayEnabled = false,
    this.pauseStartedAt,
  });

  final List<Candle> candles;
  final Timeframe timeframe;
  final bool glowEnabled;

  /// When false, the chart's vertical price range is frozen instead of
  /// re-fitting to the visible candles each frame.
  final bool autoScaleEnabled;

  /// When true, a translucent volume area chart is drawn behind the
  /// candles across the full plot area.
  final bool volumeOverlayEnabled;

  /// When non-null, drives the live growing "DATA UNAVAILABLE" gap.
  final DateTime? pauseStartedAt;

  /// Discrete real-world events to overlay on the timeline.
  final List<MarketEvent> events;

  /// User trade executions for the active symbol. Surfaced as
  /// tap-to-inspect markers anchored at each fill's price.
  final List<Fill> fills;

  @override
  Widget build(BuildContext context) {
    return AnimatedCandles(
      candles: candles,
      builder: (BuildContext context, List<Candle> animatedCandles) =>
          _CustomChart(
        candles: animatedCandles,
        timeframe: timeframe,
        glowEnabled: glowEnabled,
        autoScaleEnabled: autoScaleEnabled,
        volumeOverlayEnabled: volumeOverlayEnabled,
        pauseStartedAt: pauseStartedAt,
        events: events,
        fills: fills,
      ),
    );
  }
}

class _CustomChart extends StatefulWidget {
  const _CustomChart({
    required this.candles,
    required this.timeframe,
    required this.glowEnabled,
    required this.autoScaleEnabled,
    required this.volumeOverlayEnabled,
    required this.pauseStartedAt,
    required this.events,
    required this.fills,
  });

  final List<Candle> candles;
  final Timeframe timeframe;
  final bool glowEnabled;
  final bool autoScaleEnabled;
  final bool volumeOverlayEnabled;
  final DateTime? pauseStartedAt;
  final List<MarketEvent> events;
  final List<Fill> fills;

  @override
  State<_CustomChart> createState() => _CustomChartState();
}

class _CustomChartState extends State<_CustomChart>
    with SingleTickerProviderStateMixin {
  static const double _minCandleWidth = 2.0;
  static const double _maxCandleWidth = 60.0;
  static const double _defaultCandleWidth = 8.0;
  static const double _priceLabelGutter = 64.0;
  static const double _timeLabelGutter = 22.0;

  double _candleWidth = _defaultCandleWidth;
  double? _firstVisibleIndex;

  bool _autoFollow = true;

  /// Most recently rendered price range. While `widget.autoScaleEnabled`
  /// is true this is refreshed every frame from the visible candles;
  /// while it is false this stays put so out-of-range ticks fall outside
  /// the plot.
  (double, double)? _lockedPriceRange;

  double _gestureStartCandleWidth = _defaultCandleWidth;
  double _gestureStartFirstVisibleIndex = 0;
  Offset _gestureStartFocalPoint = Offset.zero;

  /// Snapshot of `_lockedPriceRange` taken at gesture start. Used so the
  /// vertical pan offset is computed against a stable baseline instead
  /// of the per-frame updated range (which would cause runaway drift).
  (double, double)? _gestureStartLockedPriceRange;

  /// Local-coordinate position of the active long-press, or null when
  /// none.
  Offset? _crosshair;

  /// Index of the candle the crosshair was over the last time we fired
  /// a haptic bump. Reset to null on long-press end so the next press
  /// always starts with a fresh tap (rather than no feedback because
  /// the user happened to land on the same candle as last time).
  int? _lastHapticCandleIdx;

  /// Drives the "DATA UNAVAILABLE" gap to grow live while the stream is
  /// paused. Only runs while `widget.pauseStartedAt != null`.
  late final Ticker _pauseTicker;

  @override
  void initState() {
    super.initState();
    _pauseTicker = createTicker((_) {
      if (mounted) setState(() {});
    });
    if (widget.pauseStartedAt != null) _pauseTicker.start();
  }

  @override
  void didUpdateWidget(covariant _CustomChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.timeframe != widget.timeframe) {
      _firstVisibleIndex = null;
      _autoFollow = true;
      _candleWidth = _defaultCandleWidth;
      _lockedPriceRange = null;
    } else if (_firstVisibleIndex != null &&
        oldWidget.candles.isNotEmpty &&
        widget.candles.length > oldWidget.candles.length) {
      // History was extended (older data prepended). Find where the
      // prior leftmost candle now lives in the new list and shift
      // `_firstVisibleIndex` by the same offset so the user's view
      // stays anchored on the same candles. Without this, the view
      // would "jump" to show the newly loaded oldest data.
      final DateTime oldFirstTs = oldWidget.candles.first.timestamp;
      final int newIdx = widget.candles.indexWhere(
        (Candle c) => c.timestamp == oldFirstTs,
      );
      if (newIdx > 0) {
        _firstVisibleIndex = _firstVisibleIndex! + newIdx;
      }
    }
    final bool wasPaused = oldWidget.pauseStartedAt != null;
    final bool isPaused = widget.pauseStartedAt != null;
    if (isPaused && !_pauseTicker.isActive) {
      _pauseTicker.start();
    } else if (!isPaused && _pauseTicker.isActive) {
      _pauseTicker.stop();
    }
    if (wasPaused != isPaused) {
      _autoFollow = true;
    }
  }

  /// Dispatches `HistoryExtendRequested` when the user has scrolled
  /// (or scroll-zoomed) all the way to the left edge of the loaded
  /// data. The bloc itself guards against concurrent extends and
  /// against extending before any history exists, so this can be
  /// called liberally from gesture handlers.
  void _maybeRequestExtension(double newFirst) {
    if (newFirst > 0.0) return;
    if (widget.candles.isEmpty) return;
    context.read<ChartBloc>().add(const HistoryExtendRequested());
  }

  @override
  void dispose() {
    _pauseTicker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    if (widget.candles.isEmpty) {
      return Center(
        child: Text(
          'Waiting for ticks…',
          style: t.typography.bodySm.copyWith(
            color: t.colors.contentTertiary,
          ),
        ),
      );
    }
    final TextStyle labelStyle = t.typography.labelSm.copyWith(
      color: t.colors.contentTertiary,
      letterSpacing: 0.4,
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size size = Size(constraints.maxWidth, constraints.maxHeight);
        final Rect plotArea = Rect.fromLTRB(
          0,
          8,
          size.width - _priceLabelGutter,
          size.height - _timeLabelGutter,
        );

        final double gapInCandles = _activeGapInCandles();
        final double virtualLength = widget.candles.length + gapInCandles;

        final double visibleCount =
            math.max(plotArea.width / _candleWidth, 1.0);
        final double maxFirst = math.max(0.0, virtualLength - visibleCount);

        if (_firstVisibleIndex == null || _autoFollow) {
          _firstVisibleIndex = maxFirst;
        } else {
          _firstVisibleIndex = _firstVisibleIndex!.clamp(0.0, maxFirst);
        }
        final double firstVisibleIndex = _firstVisibleIndex!;

        final (double, double)? priceRange;
        if (widget.autoScaleEnabled) {
          priceRange = CandlePainter.visiblePriceRange(
                candles: widget.candles,
                firstVisibleIndex: firstVisibleIndex,
                candleWidth: _candleWidth,
                plotWidth: plotArea.width,
              ) ??
              _fallbackPriceRange();
          _lockedPriceRange = priceRange;
        } else {
          priceRange = _lockedPriceRange ??
              CandlePainter.visiblePriceRange(
                candles: widget.candles,
                firstVisibleIndex: firstVisibleIndex,
                candleWidth: _candleWidth,
                plotWidth: plotArea.width,
              ) ??
              _fallbackPriceRange();
          _lockedPriceRange ??= priceRange;
        }

        final Candle? touchedCandle = _crosshair == null
            ? null
            : _candleAtX(_crosshair!.dx, plotArea, firstVisibleIndex);
        final int? highlightedIdx = _crosshair == null
            ? null
            : _indexAtX(_crosshair!.dx, plotArea, firstVisibleIndex);

        return Listener(
          onPointerSignal: (PointerSignalEvent signal) {
            if (signal is PointerScrollEvent) {
              _onScrollZoom(signal, plotArea);
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: (ScaleStartDetails details) {
              _gestureStartCandleWidth = _candleWidth;
              _gestureStartFirstVisibleIndex = firstVisibleIndex;
              _gestureStartFocalPoint = details.localFocalPoint;
              _gestureStartLockedPriceRange = _lockedPriceRange;
            },
            onScaleUpdate: (ScaleUpdateDetails details) =>
                _onScaleUpdate(details, plotArea, maxFirst),
            onLongPressStart: (LongPressStartDetails details) {
              setState(() {
                _crosshair = details.localPosition;
                _autoFollow = false;
              });
              _maybeBumpHaptic(details.localPosition, plotArea);
            },
            onLongPressMoveUpdate: (LongPressMoveUpdateDetails details) {
              setState(() => _crosshair = details.localPosition);
              _maybeBumpHaptic(details.localPosition, plotArea);
            },
            onLongPressEnd: (_) {
              setState(() => _crosshair = null);
              _lastHapticCandleIdx = null;
            },
            onLongPressCancel: () {
              setState(() => _crosshair = null);
              _lastHapticCandleIdx = null;
            },
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: CustomPaint(
                    painter: priceRange != null
                        ? ChartAxesPainter(
                            candles: widget.candles,
                            firstVisibleIndex: firstVisibleIndex,
                            candleWidth: _candleWidth,
                            minPrice: priceRange.$1,
                            maxPrice: priceRange.$2,
                            plotArea: plotArea,
                            gridColor:
                                t.colors.chartGrid.withValues(alpha: 0.6),
                            labelStyle: labelStyle,
                            timeframe: widget.timeframe,
                          )
                        : null,
                    foregroundPainter: CandlePainter(
                      candles: widget.candles,
                      firstVisibleIndex: firstVisibleIndex,
                      candleWidth: _candleWidth,
                      bullishColor: t.colors.chartCandleBullish,
                      bearishColor: t.colors.chartCandleBearish,
                      plotArea: plotArea,
                      gapFillColor: t.colors.chartGapWarningSurface,
                      gapIconColor: t.colors.chartGapWarning,
                      glowSigma: widget.glowEnabled ? 4.0 : 0.0,
                      priceRangeOverride: priceRange,
                      highlightedIndex: highlightedIdx,
                    ),
                    // Mid-layer Stack — anything inside paints AFTER
                    // the axes painter and BEFORE the candle
                    // foregroundPainter, so the volume backdrop and
                    // long-press crosshair both sit behind the candle
                    // bodies.
                    child: Stack(
                      children: <Widget>[
                        if (widget.volumeOverlayEnabled)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: AnimatedVolumeOverlay(
                                candles: widget.candles,
                                firstVisibleIndex: firstVisibleIndex,
                                candleWidth: _candleWidth,
                                plotArea: Rect.fromLTRB(
                                  plotArea.left,
                                  plotArea.top + plotArea.height * 0.75,
                                  plotArea.right,
                                  plotArea.bottom,
                                ),
                                lineColor: t.colors.chartVolumeArea,
                              ),
                            ),
                          ),
                        if (_crosshair != null)
                          Positioned.fill(
                            child: IgnorePointer(
                              child: CustomPaint(
                                painter: CrosshairPainter(
                                  position: _crosshair,
                                  color: t.colors.chartCrosshair,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (gapInCandles > 0)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: MissingDataPainter(
                          startCandleIndex:
                              widget.candles.length.toDouble(),
                          firstVisibleIndex: firstVisibleIndex,
                          candleWidth: _candleWidth,
                          gapInCandles: gapInCandles,
                          plotArea: plotArea,
                          fillColor: t.colors.chartGapWarningSurface,
                          iconColor: t.colors.chartGapWarning,
                        ),
                      ),
                    ),
                  ),
                if (widget.events.isNotEmpty)
                  Positioned.fill(
                    child: EventMarkerOverlay(
                      events: widget.events,
                      candles: widget.candles,
                      timeframe: widget.timeframe,
                      firstVisibleIndex: firstVisibleIndex,
                      candleWidth: _candleWidth,
                      plotArea: plotArea,
                    ),
                  ),
                // Fill markers paint over the candles + event row but
                // below the crosshair tooltip, so a tap on a fill
                // doesn't get swallowed by the tooltip's invisible
                // hit region (the tooltip widget is conditionally
                // mounted further down only when there's an active
                // long-press).
                if (widget.fills.isNotEmpty && priceRange != null)
                  Positioned.fill(
                    child: FillMarkerOverlay(
                      fills: widget.fills,
                      candles: widget.candles,
                      timeframe: widget.timeframe,
                      firstVisibleIndex: firstVisibleIndex,
                      candleWidth: _candleWidth,
                      plotArea: plotArea,
                      priceRange: priceRange,
                    ),
                  ),
                if (touchedCandle != null && _crosshair != null)
                  _positionedTooltip(
                    size: size,
                    crosshair: _crosshair!,
                    candle: touchedCandle,
                  ),
                if (!_autoFollow && _crosshair == null)
                  Positioned(
                    // Sits just inside the price-label gutter on the
                    // right edge of the plot area. Hidden while the
                    // user is long-pressing (`_crosshair != null`)
                    // so it never overlaps the OHLC tooltip.
                    right: _priceLabelGutter + 8,
                    top: 12,
                    child: _LiveButton(
                      onTap: () {
                        final double visible =
                            math.max(plotArea.width / _candleWidth, 1.0);
                        final double liveMax =
                            math.max(0.0, _virtualLength() - visible);

                        // With auto-scale off the band stays frozen
                        // wherever the user panned it — re-center it
                        // on the latest real close so the live tick is
                        // actually visible after we jump back.
                        (double, double)? recenteredRange;
                        if (!widget.autoScaleEnabled &&
                            _lockedPriceRange != null) {
                          final double? latestPrice = _latestRealClose();
                          if (latestPrice != null) {
                            final double span = _lockedPriceRange!.$2 -
                                _lockedPriceRange!.$1;
                            recenteredRange = (
                              latestPrice - span / 2,
                              latestPrice + span / 2,
                            );
                          }
                        }

                        setState(() {
                          _autoFollow = true;
                          _firstVisibleIndex = liveMax;
                          if (recenteredRange != null) {
                            _lockedPriceRange = recenteredRange;
                          }
                        });
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Last-resort price range when the visible window contains only gap
  /// slots. Walks back through the full candle history for the most
  /// recent real candle and stretches a small band around its close.
  (double, double)? _fallbackPriceRange() {
    final double? latest = _latestRealClose();
    if (latest == null) return null;
    final double pad = math.max(latest * 0.02, 1.0);
    return (latest - pad, latest + pad);
  }

  /// Walks back through the candle history for the close price of the
  /// most recent non-gap candle.
  double? _latestRealClose() {
    for (int i = widget.candles.length - 1; i >= 0; i--) {
      final Candle c = widget.candles[i];
      if (c.isGap) continue;
      return c.close;
    }
    return null;
  }

  /// Converts elapsed pause time to candle-widths so the gap can be
  /// drawn inline with the candle layout.
  double _activeGapInCandles() {
    final DateTime? pausedAt = widget.pauseStartedAt;
    if (pausedAt == null) return 0;
    final double elapsedMs =
        DateTime.now().difference(pausedAt).inMilliseconds.toDouble();
    final double tfMs = widget.timeframe.duration.inMilliseconds.toDouble();
    if (tfMs <= 0) return 0;
    return elapsedMs / tfMs;
  }

  /// Total horizontal extent in candle-units: real candles plus the
  /// active growing gap (if paused).
  double _virtualLength() => widget.candles.length + _activeGapInCandles();

  Candle? _candleAtX(double localX, Rect plotArea, double firstVisibleIndex) {
    final int? idx = _indexAtX(localX, plotArea, firstVisibleIndex);
    if (idx == null) return null;
    return widget.candles[idx];
  }

  int? _indexAtX(double localX, Rect plotArea, double firstVisibleIndex) {
    if (_candleWidth <= 0 || widget.candles.isEmpty) return null;
    final double relative = localX - plotArea.left;
    if (relative < 0 || relative > plotArea.width) return null;
    final int idx = (firstVisibleIndex + relative / _candleWidth).floor();
    if (idx < 0 || idx >= widget.candles.length) return null;
    if (widget.candles[idx].isGap) return null;
    return idx;
  }

  /// Fires a light selection-click haptic whenever the crosshair
  /// crosses from one real candle to another during a long-press
  /// inspection.
  void _maybeBumpHaptic(Offset position, Rect plotArea) {
    final double? firstVisible = _firstVisibleIndex;
    if (firstVisible == null) return;
    final int? idx = _indexAtX(position.dx, plotArea, firstVisible);
    if (idx == null || idx == _lastHapticCandleIdx) return;
    _lastHapticCandleIdx = idx;
    HapticFeedback.selectionClick();
  }

  Widget _positionedTooltip({
    required Size size,
    required Offset crosshair,
    required Candle candle,
  }) {
    const double margin = 12.0;
    // Place the tooltip in whichever top corner is opposite the touch
    // x, so it never overlaps the candle the user is inspecting.
    final bool placeOnLeft = crosshair.dx > size.width * 0.5;
    return Positioned(
      top: margin,
      left: placeOnLeft ? margin : null,
      right: placeOnLeft ? null : margin,
      child: IgnorePointer(child: OhlcTooltip(candle: candle)),
    );
  }

  void _onScaleUpdate(
    ScaleUpdateDetails details,
    Rect plotArea,
    double maxFirst,
  ) {
    final double newCandleWidth =
        (_gestureStartCandleWidth * details.scale).clamp(
      _minCandleWidth,
      _maxCandleWidth,
    );

    final double dx =
        _gestureStartFocalPoint.dx - details.localFocalPoint.dx;
    final double panInCandles = dx / newCandleWidth;
    double newFirst = _gestureStartFirstVisibleIndex + panInCandles;

    final double focalRatio =
        (details.localFocalPoint.dx - plotArea.left) / plotArea.width;
    final double prevVisible = plotArea.width / _gestureStartCandleWidth;
    final double newVisible = plotArea.width / newCandleWidth;
    newFirst -= (newVisible - prevVisible) * focalRatio;

    final double newMaxFirst =
        math.max(0.0, _virtualLength() - newVisible);
    newFirst = newFirst.clamp(0.0, newMaxFirst);

    (double, double)? newLockedRange;
    if (!widget.autoScaleEnabled &&
        _gestureStartLockedPriceRange != null &&
        plotArea.height > 0) {
      final double startMin = _gestureStartLockedPriceRange!.$1;
      final double startMax = _gestureStartLockedPriceRange!.$2;
      final double startSpan = startMax - startMin;
      final double dy =
          details.localFocalPoint.dy - _gestureStartFocalPoint.dy;
      final double priceDelta = (dy / plotArea.height) * startSpan;
      newLockedRange = (startMin + priceDelta, startMax + priceDelta);
    }

    setState(() {
      _candleWidth = newCandleWidth;
      _firstVisibleIndex = newFirst;
      _autoFollow = newFirst >= newMaxFirst - 0.5;
      if (newLockedRange != null) {
        _lockedPriceRange = newLockedRange;
      }
    });
    _maybeRequestExtension(newFirst);
  }

  void _onScrollZoom(PointerScrollEvent signal, Rect plotArea) {
    final double factor = signal.scrollDelta.dy > 0 ? 0.9 : 1.1;
    final double newCandleWidth =
        (_candleWidth * factor).clamp(_minCandleWidth, _maxCandleWidth);
    final double focalX = signal.localPosition.dx - plotArea.left;
    final double focalRatio = (focalX / plotArea.width).clamp(0.0, 1.0);

    final double prevVisible = plotArea.width / _candleWidth;
    final double newVisible = plotArea.width / newCandleWidth;

    double newFirst = (_firstVisibleIndex ?? 0) -
        (newVisible - prevVisible) * focalRatio;
    final double newMaxFirst =
        math.max(0.0, _virtualLength() - newVisible);
    newFirst = newFirst.clamp(0.0, newMaxFirst);

    setState(() {
      _candleWidth = newCandleWidth;
      _firstVisibleIndex = newFirst;
      _autoFollow = newFirst >= newMaxFirst - 0.5;
    });
    _maybeRequestExtension(newFirst);
  }
}

/// Floating "LIVE >" pill shown when the user has panned away from the
/// right edge. Tapping it snaps the chart back to live data and resumes
/// auto-follow.
class _LiveButton extends StatefulWidget {
  const _LiveButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_LiveButton> createState() => _LiveButtonState();
}

class _LiveButtonState extends State<_LiveButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    final BorderRadius pillRadius = t.radii.xlAll;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (BuildContext context, Widget? child) {
        final double tValue = Curves.easeInOut.transform(_ctrl.value);
        return Container(
          decoration: BoxDecoration(
            borderRadius: pillRadius,
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: t.colors.chartCandleBullish.withValues(
                  alpha: 0.25 + 0.35 * tValue,
                ),
                blurRadius: 12 + 8 * tValue,
                spreadRadius: 1 + 2 * tValue,
              ),
            ],
          ),
          child: child,
        );
      },
      child: Material(
        color: t.colors.chartCandleBullish,
        borderRadius: pillRadius,
        elevation: 4,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: pillRadius,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: t.spacing.md + 2,
              vertical: t.spacing.sm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'LIVE',
                  style: t.typography.labelMd.copyWith(
                    color: t.colors.contentInverse,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(width: t.spacing.xs + 2),
                Icon(
                  Icons.chevron_right,
                  color: t.colors.contentInverse,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
