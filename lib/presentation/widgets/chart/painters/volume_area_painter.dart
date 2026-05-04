import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../data/models/candle.dart';

/// Translucent line+gradient area chart of per-candle volume, drawn behind
/// the candles to give a Robinhood-style "intraday volume backdrop".
///
/// Visually mirrors the bottom-left minimap (line on top, gradient
/// fading to transparent below it) but stretched across the full plot
/// area and tinted light purple so it doesn't compete with the
/// green/red of the candles.
///
/// Volume is normalised against the visible window's max so the curve's
/// peak always touches the top of the plot — this is intentional: the
/// backdrop's purpose is showing relative activity, not absolute share
/// counts. Gaps break the line so missing data doesn't get connected
/// across the void.
class VolumeAreaPainter extends CustomPainter {
  VolumeAreaPainter({
    required this.candles,
    required this.firstVisibleIndex,
    required this.candleWidth,
    required this.plotArea,
    required this.lineColor,
    this.previousVolumes,
    this.animationT = 1.0,
    this.pulsePhase = 0.0,
  });

  final List<Candle> candles;
  final double firstVisibleIndex;
  final double candleWidth;
  final Rect plotArea;
  final Color lineColor;

  /// Volume value each candle was rendering with at the start of the
  /// current transition, keyed by candle timestamp. When [animationT] < 1
  /// the painter interpolates from this snapshot toward `candle.volume`.
  /// The wrapper widget is responsible for applying any easing curve to
  /// [animationT] before passing it in — the painter just lerps.
  final Map<int, double>? previousVolumes;

  /// Eased progress (0..1) of the in-flight transition from
  /// [previousVolumes] to the current `candle.volume`s.
  final double animationT;

  /// Continuous 0..1 phase fed from the wrapper's repeating pulse
  /// controller. Mapped through `sin(2π·t)` to give the "LIVE" tip
  /// indicator a smooth in-out heartbeat.
  final double pulsePhase;

  /// True if [i] is the just-emerged rightmost candle: it has no entry
  /// in [previousVolumes] AND it's the last index. Restricting the
  /// emerge effect to the newest candle keeps backfills from animating
  /// (history candles get added on the left and would otherwise slide
  /// in cascade).
  bool _isEmergingRightmost(int i, Candle c) {
    if (previousVolumes == null) return false;
    if (i != candles.length - 1) return false;
    if (i == 0) return false;
    return !previousVolumes!.containsKey(c.timestamp.millisecondsSinceEpoch);
  }

  /// Resolves the volume to draw for the candle at [i] right now,
  /// lerping from the previous snapshot toward the live value. The
  /// just-emerged rightmost candle starts at the previous candle's
  /// volume so the new line segment grows out of the existing curve
  /// instead of popping in.
  double _displayedVolume(int i, Candle c) {
    final int key = c.timestamp.millisecondsSinceEpoch;
    final double? prev = previousVolumes?[key];
    if (prev != null) {
      return ui.lerpDouble(prev, c.volume, animationT) ?? c.volume;
    }
    if (_isEmergingRightmost(i, c)) {
      final Candle prevC = candles[i - 1];
      final double prevV =
          previousVolumes![prevC.timestamp.millisecondsSinceEpoch] ??
              prevC.volume;
      return ui.lerpDouble(prevV, c.volume, animationT) ?? c.volume;
    }
    return c.volume;
  }

  /// Effective horizontal slot used for x-positioning. Only the newly-
  /// emerged rightmost candle gets a non-identity value: it lerps from
  /// the previous candle's index toward its own, sliding the new tip
  /// out from the prior endpoint over the course of the animation.
  double _displayedIndex(int i, Candle c) {
    if (!_isEmergingRightmost(i, c)) return i.toDouble();
    return ui.lerpDouble((i - 1).toDouble(), i.toDouble(), animationT) ??
        i.toDouble();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty || candleWidth <= 0 || plotArea.width <= 0) return;

    final int visibleCount = (plotArea.width / candleWidth).ceil() + 1;
    final int startIdx =
        firstVisibleIndex.floor().clamp(0, candles.length - 1);
    final int endIdx = (startIdx + visibleCount).clamp(0, candles.length);
    if (startIdx >= endIdx) return;

    // Normalise against the eased peak so the y-axis scale itself
    // glides in tandem with the line, avoiding a "rest of the chart
    // pops down while the new bar grows" effect.
    double maxV = 0.0;
    for (int i = startIdx; i < endIdx; i++) {
      final Candle c = candles[i];
      if (c.isGap) continue;
      final double v = _displayedVolume(i, c);
      if (v > maxV) maxV = v;
    }
    if (maxV <= 0) return;

    double xFor(int i) {
      final double idx = _displayedIndex(i, candles[i]);
      return plotArea.left +
          (idx - firstVisibleIndex) * candleWidth +
          candleWidth / 2;
    }

    double yFor(double v) =>
        plotArea.bottom - (v / maxV) * plotArea.height;

    canvas.save();
    canvas.clipRect(plotArea);

    final Paint linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final ui.Shader fillShader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: <Color>[
        lineColor.withValues(alpha: 0.35),
        lineColor.withValues(alpha: 0.0),
      ],
    ).createShader(plotArea);

    int? lastDrawnIdx;

    int? runStart;
    void flushRun(int runEndExclusive) {
      if (runStart == null) return;
      final int start = runStart!;
      final int endIncl = runEndExclusive - 1;
      runStart = null;
      if (endIncl < start) return;

      final Path linePath = Path();
      for (int i = start; i <= endIncl; i++) {
        final double x = xFor(i);
        final double y = yFor(_displayedVolume(i, candles[i]));
        if (i == start) {
          linePath.moveTo(x, y);
        } else {
          linePath.lineTo(x, y);
        }
      }

      final Path fillPath = Path.from(linePath)
        ..lineTo(xFor(endIncl), plotArea.bottom)
        ..lineTo(xFor(start), plotArea.bottom)
        ..close();

      canvas.drawPath(fillPath, Paint()..shader = fillShader);
      if (endIncl > start) {
        canvas.drawPath(linePath, linePaint);
      }
      lastDrawnIdx = endIncl;
    }

    for (int i = startIdx; i < endIdx; i++) {
      if (candles[i].isGap) {
        flushRun(i);
      } else {
        runStart ??= i;
      }
    }
    flushRun(endIdx);

    canvas.restore();

    // Draw the pulsing "LIVE" tip indicator only when the rightmost
    // visible endpoint is actually the latest candle in the dataset —
    // i.e. the user is looking at live data, not panned back into
    // history. Painted after `restore()` so the label can extend
    // outside the bottom-quarter clip without being chopped.
    if (lastDrawnIdx != null && lastDrawnIdx == candles.length - 1) {
      final int i = lastDrawnIdx!;
      final Candle c = candles[i];
      final Offset tip = Offset(xFor(i), yFor(_displayedVolume(i, c)));
      _paintLiveTip(canvas, tip);
    }
  }

  /// Paints the heartbeat dot at the line's rightmost endpoint. The
  /// pulse is a `(sin(2π·t) + 1) / 2` oscillation so the glow grows
  /// and fades smoothly without an audible step at the loop boundary.
  void _paintLiveTip(Canvas canvas, Offset tip) {
    final double pulse = (math.sin(pulsePhase * 2 * math.pi) + 1) / 2;

    final double glowRadius = 5.5 + pulse * 7.0;
    final Paint glowPaint = Paint()
      ..color = lineColor.withValues(alpha: 0.10 + pulse * 0.30)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
    canvas.drawCircle(tip, glowRadius, glowPaint);

    final Paint dotPaint = Paint()
      ..color = lineColor
      ..isAntiAlias = true;
    canvas.drawCircle(tip, 3.0, dotPaint);
  }

  @override
  bool shouldRepaint(covariant VolumeAreaPainter old) =>
      old.candles != candles ||
      old.firstVisibleIndex != firstVisibleIndex ||
      old.candleWidth != candleWidth ||
      old.plotArea != plotArea ||
      old.lineColor != lineColor ||
      old.previousVolumes != previousVolumes ||
      old.animationT != animationT ||
      old.pulsePhase != pulsePhase;
}
