import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../data/models/candle.dart';
import 'painters/volume_area_painter.dart';

/// Hosts the [VolumeAreaPainter] and tweens between successive volume
/// snapshots with an ease-out curve so the purple line glides toward
/// new values rather than snapping. Each new candle list captures the
/// currently-displayed (already-eased) volumes as the new "from" state
/// and restarts the animation toward the new "to" state.
class AnimatedVolumeOverlay extends StatefulWidget {
  const AnimatedVolumeOverlay({
    super.key,
    required this.candles,
    required this.firstVisibleIndex,
    required this.candleWidth,
    required this.plotArea,
    required this.lineColor,
    this.duration = const Duration(milliseconds: 220),
    this.curve = Curves.easeInOutQuad,
    this.pulsePeriod = const Duration(milliseconds: 1500),
  });

  final List<Candle> candles;
  final double firstVisibleIndex;
  final double candleWidth;
  final Rect plotArea;
  final Color lineColor;

  /// How long to take interpolating between the old and new volume
  /// snapshots. Slightly longer than the typical tick interval reads as
  /// a smooth, continuous curve.
  final Duration duration;

  /// Easing applied on top of the controller's linear progress.
  /// Quadratic ease-in-out gives a symmetric "settle in, settle out"
  /// feel.
  final Curve curve;

  /// Period of the looping "LIVE" tip pulse. The painter maps the
  /// controller's 0..1 phase through `sin(2π·t)`, so one pulsePeriod
  /// gives exactly one breath cycle.
  final Duration pulsePeriod;

  @override
  State<AnimatedVolumeOverlay> createState() => _AnimatedVolumeOverlayState();
}

class _AnimatedVolumeOverlayState extends State<AnimatedVolumeOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _controller;
  late final AnimationController _pulseController;

  Map<int, double> _previousVolumes = const <int, double>{};

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: 1.0,
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: widget.pulsePeriod,
    )..repeat();
    _previousVolumes = _captureLive(widget.candles);
  }

  @override
  void didUpdateWidget(covariant AnimatedVolumeOverlay old) {
    super.didUpdateWidget(old);
    if (widget.duration != old.duration) {
      _controller.duration = widget.duration;
    }
    if (widget.pulsePeriod != old.pulsePeriod) {
      _pulseController
        ..stop()
        ..duration = widget.pulsePeriod
        ..repeat();
    }
    if (_volumesChanged(old.candles, widget.candles)) {
      // Freeze whatever is currently on screen (mid-tween value, not
      // the raw old volume) as the new baseline so the next animation
      // picks up from the visible position with no discontinuity.
      _previousVolumes = _captureDisplayed(old.candles);
      _controller
        ..stop()
        ..forward(from: 0);
    }
  }

  bool _volumesChanged(List<Candle> a, List<Candle> b) {
    if (identical(a, b)) return false;
    if (a.length != b.length) return true;
    for (int i = 0; i < a.length; i++) {
      if (a[i].volume != b[i].volume) return true;
    }
    return false;
  }

  Map<int, double> _captureLive(List<Candle> candles) {
    final Map<int, double> out = <int, double>{};
    for (final Candle c in candles) {
      out[c.timestamp.millisecondsSinceEpoch] = c.volume;
    }
    return out;
  }

  Map<int, double> _captureDisplayed(List<Candle> candles) {
    final Map<int, double> out = <int, double>{};
    final double t = widget.curve.transform(_controller.value);
    for (int i = 0; i < candles.length; i++) {
      final Candle c = candles[i];
      final int key = c.timestamp.millisecondsSinceEpoch;
      final double? prev = _previousVolumes[key];
      if (prev != null) {
        out[key] = ui.lerpDouble(prev, c.volume, t) ?? c.volume;
        continue;
      }
      if (i == candles.length - 1 && i > 0) {
        final Candle prevC = candles[i - 1];
        final double pv =
            _previousVolumes[prevC.timestamp.millisecondsSinceEpoch] ??
                prevC.volume;
        out[key] = ui.lerpDouble(pv, c.volume, t) ?? c.volume;
      } else {
        out[key] = c.volume;
      }
    }
    return out;
  }

  @override
  void dispose() {
    _controller.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[_controller, _pulseController]),
      builder: (BuildContext context, Widget? _) {
        return CustomPaint(
          painter: VolumeAreaPainter(
            candles: widget.candles,
            firstVisibleIndex: widget.firstVisibleIndex,
            candleWidth: widget.candleWidth,
            plotArea: widget.plotArea,
            lineColor: widget.lineColor,
            previousVolumes: _previousVolumes,
            animationT: widget.curve.transform(_controller.value),
            pulsePhase: _pulseController.value,
          ),
        );
      },
    );
  }
}
