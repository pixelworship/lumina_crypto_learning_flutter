import 'dart:math' show min;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../../data/models/candle.dart';

/// Linearly interpolates two candle lists element-wise.
///
/// - Equal-length lists: each candle's OHLC + volume is lerped at [t].
/// - The new list has more candles: extra candles animate in from a flat
///   point at their open price.
/// - The new list has fewer candles: extras are dropped immediately.
List<Candle> lerpCandles(List<Candle> from, List<Candle> to, double t) {
  if (t >= 1.0 || from.isEmpty || to.isEmpty) return to;

  // Walk from the end to find the first index that actually changed.
  // In practice ticks only mutate the last 1–2 candles, so this
  // terminates fast.
  final int commonLen = min(from.length, to.length);
  int firstDiff = commonLen;
  for (int i = commonLen - 1; i >= 0; i--) {
    if (from[i] == to[i]) break;
    firstDiff = i;
  }
  if (to.length > from.length) {
    firstDiff = min(firstDiff, from.length);
  }
  if (firstDiff >= to.length) return to;

  final List<Candle> result = List<Candle>.of(to);
  for (int i = firstDiff; i < to.length; i++) {
    final Candle target = to[i];
    if (target.isGap) {
      result[i] = target;
      continue;
    }
    if (i < from.length && !from[i].isGap) {
      final Candle source = from[i];
      result[i] = Candle(
        timestamp: target.timestamp,
        open: lerpDouble(source.open, target.open, t)!,
        high: lerpDouble(source.high, target.high, t)!,
        low: lerpDouble(source.low, target.low, t)!,
        close: lerpDouble(source.close, target.close, t)!,
        volume: lerpDouble(source.volume, target.volume, t)!,
      );
    } else {
      result[i] = Candle(
        timestamp: target.timestamp,
        open: target.open,
        high: lerpDouble(target.open, target.high, t)!,
        low: lerpDouble(target.open, target.low, t)!,
        close: lerpDouble(target.open, target.close, t)!,
        volume: lerpDouble(0, target.volume, t)!,
      );
    }
  }
  return result;
}

/// Whether moving from [a] to [b] should snap (no animation) — i.e. the
/// underlying data structure changed too much (e.g. timeframe rebuild).
bool _shouldSnap(List<Candle> a, List<Candle> b) {
  if (a.isEmpty || b.isEmpty) return true;
  if ((a.length - b.length).abs() > 1) return true;
  if (a.first.timestamp != b.first.timestamp) return true;
  return false;
}

/// Wraps a list of candles in a linear animation. On each update, kicks
/// off a new tween from the current interpolated state to the new
/// target list.
class AnimatedCandles extends StatefulWidget {
  const AnimatedCandles({
    super.key,
    required this.candles,
    required this.builder,
    this.duration = const Duration(milliseconds: 220),
    this.curve = Curves.easeInOut,
  });

  final List<Candle> candles;
  final Duration duration;
  final Curve curve;
  final Widget Function(BuildContext context, List<Candle> candles) builder;

  @override
  State<AnimatedCandles> createState() => _AnimatedCandlesState();
}

class _AnimatedCandlesState extends State<AnimatedCandles>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late CurvedAnimation _curved;
  List<Candle> _from = const <Candle>[];
  List<Candle> _to = const <Candle>[];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..addListener(() {
        if (mounted) setState(() {});
      });
    _curved = CurvedAnimation(parent: _controller, curve: widget.curve);
    _from = widget.candles;
    _to = widget.candles;
  }

  @override
  void didUpdateWidget(covariant AnimatedCandles oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration != oldWidget.duration) {
      _controller.duration = widget.duration;
    }
    if (widget.curve != oldWidget.curve) {
      _curved.dispose();
      _curved = CurvedAnimation(parent: _controller, curve: widget.curve);
    }
    if (!identical(widget.candles, _to)) {
      if (_shouldSnap(_to, widget.candles)) {
        _from = widget.candles;
        _to = widget.candles;
        _controller.value = 1.0;
      } else {
        _from = _currentCandles();
        _to = widget.candles;
        _controller
          ..reset()
          ..forward();
      }
    }
  }

  List<Candle> _currentCandles() => lerpCandles(_from, _to, _curved.value);

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _currentCandles());
  }

  @override
  void dispose() {
    _curved.dispose();
    _controller.dispose();
    super.dispose();
  }
}
