import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/utils/perlin_noise.dart';
import '../../../design_system/lumina_ui.dart';
import '../../blocs/chart/chart_bloc.dart';
import '../../blocs/chart/chart_state.dart';

/// Animated lava-lamp background that wraps [child].
///
/// Many large radial gradients drift around the available area driven by
/// independent Perlin noise per blob, blended with [BlendMode.screen]
/// inside a single saved layer so overlaps brighten gracefully. Color
/// smoothly transitions between bullish/bearish based on the latest
/// candle.
class PriceFlashOverlay extends StatefulWidget {
  const PriceFlashOverlay({
    super.key,
    required this.child,
    this.bullishColor,
    this.bearishColor,
    this.colorDuration = const Duration(milliseconds: 600),
    this.blobCount = 40,
    this.minBlobOpacity = 0.01,
    this.maxBlobOpacity = 0.05,
    this.minBlobSpeed = 0.035,
    this.maxBlobSpeed = 0.09,
    this.minBlobSize = 0.32,
    this.maxBlobSize = 0.58,
  });

  final Widget child;

  /// Override the bullish color used for the lava blobs. Defaults to
  /// `t.colors.chartCandleBullish` when null.
  final Color? bullishColor;

  /// Override the bearish color. Defaults to `t.colors.chartCandleBearish`.
  final Color? bearishColor;
  final Duration colorDuration;

  final int blobCount;
  final double minBlobOpacity;
  final double maxBlobOpacity;
  final double minBlobSpeed;
  final double maxBlobSpeed;
  final double minBlobSize;
  final double maxBlobSize;

  @override
  State<PriceFlashOverlay> createState() => _PriceFlashOverlayState();
}

class _PriceFlashOverlayState extends State<PriceFlashOverlay>
    with TickerProviderStateMixin {
  late final Ticker _ticker;
  late final AnimationController _colorCtrl;
  late Animation<Color?> _color;
  late final List<_BlobConfig> _blobs;
  late final PerlinNoise1D _noise;

  double _elapsedSeconds = 0;
  bool? _trackedBullish;
  bool _glowEnabled = true;

  @override
  void initState() {
    super.initState();
    _noise = PerlinNoise1D(seed: 0xBEEF);

    final Random rng = Random();
    double randIn(double min, double max) =>
        min + rng.nextDouble() * (max - min);

    _blobs = List<_BlobConfig>.generate(
      widget.blobCount,
      (_) => _BlobConfig(
        phaseX: randIn(0, 1000),
        phaseY: randIn(0, 1000),
        speedX: randIn(widget.minBlobSpeed, widget.maxBlobSpeed),
        speedY: randIn(widget.minBlobSpeed, widget.maxBlobSpeed),
        sizeFactor: randIn(widget.minBlobSize, widget.maxBlobSize),
        maxOpacity: randIn(widget.minBlobOpacity, widget.maxBlobOpacity),
      ),
    );

    _ticker = createTicker((Duration elapsed) {
      _elapsedSeconds = elapsed.inMicroseconds / 1e6;
      if (mounted) setState(() {});
    });

    _colorCtrl = AnimationController(
      vsync: this,
      duration: widget.colorDuration,
      value: 1.0,
    )..addListener(() {
        if (mounted) setState(() {});
      });
    _color = ColorTween(
      begin: const Color(0xFF000000),
      end: const Color(0xFF000000),
    ).animate(_colorCtrl);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_trackedBullish == null) {
      final ChartState state = context.read<ChartBloc>().state;
      final bool initial = _bullishFromState(state);
      _trackedBullish = initial;
      final Color color = initial ? _bullishColor : _bearishColor;
      _color = ColorTween(begin: color, end: color).animate(_colorCtrl);
      _glowEnabled = state.glowEnabled;
      if (_glowEnabled && !_ticker.isActive) {
        _ticker.start();
      }
    }
  }

  @override
  void didUpdateWidget(covariant PriceFlashOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.colorDuration != widget.colorDuration) {
      _colorCtrl.duration = widget.colorDuration;
    }
  }

  Color get _bullishColor =>
      widget.bullishColor ?? context.tokens.colors.chartCandleBullish;
  Color get _bearishColor =>
      widget.bearishColor ?? context.tokens.colors.chartCandleBearish;

  bool _bullishFromState(ChartState state) {
    if (state.candles.isEmpty) return true;
    return state.candles.last.isBullish;
  }

  void _onStateChanged(BuildContext _, ChartState state) {
    final bool bullish = _bullishFromState(state);
    if (bullish != _trackedBullish) {
      _trackedBullish = bullish;
      final Color from = _color.value ?? _bullishColor;
      final Color to = bullish ? _bullishColor : _bearishColor;
      _color = ColorTween(begin: from, end: to).animate(
        CurvedAnimation(parent: _colorCtrl, curve: Curves.easeInOut),
      );
      _colorCtrl
        ..reset()
        ..forward();
    }

    if (state.glowEnabled != _glowEnabled) {
      setState(() => _glowEnabled = state.glowEnabled);
      if (_glowEnabled) {
        if (!_ticker.isActive) _ticker.start();
      } else {
        if (_ticker.isActive) _ticker.stop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color color = _color.value ?? _bullishColor;
    return BlocListener<ChartBloc, ChartState>(
      listenWhen: (ChartState prev, ChartState next) =>
          _bullishFromState(prev) != _bullishFromState(next) ||
          prev.glowEnabled != next.glowEnabled,
      listener: _onStateChanged,
      child: Stack(
        children: <Widget>[
          if (_glowEnabled)
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _LavaLampPainter(
                      blobs: _blobs,
                      color: color,
                      elapsedSeconds: _elapsedSeconds,
                      noise: _noise,
                    ),
                  ),
                ),
              ),
            ),
          widget.child,
        ],
      ),
    );
  }

  @override
  void dispose() {
    _ticker.dispose();
    _colorCtrl.dispose();
    super.dispose();
  }
}

class _BlobConfig {
  const _BlobConfig({
    required this.phaseX,
    required this.phaseY,
    required this.speedX,
    required this.speedY,
    required this.sizeFactor,
    required this.maxOpacity,
  });

  final double phaseX;
  final double phaseY;
  final double speedX;
  final double speedY;
  final double sizeFactor;
  final double maxOpacity;
}

class _LavaLampPainter extends CustomPainter {
  _LavaLampPainter({
    required this.blobs,
    required this.color,
    required this.elapsedSeconds,
    required this.noise,
  });

  final List<_BlobConfig> blobs;
  final Color color;
  final double elapsedSeconds;
  final PerlinNoise1D noise;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final Rect bounds = Offset.zero & size;

    canvas.saveLayer(bounds, Paint());

    for (final _BlobConfig blob in blobs) {
      final double nx =
          noise.sample(blob.phaseX + elapsedSeconds * blob.speedX);
      final double ny =
          noise.sample(blob.phaseY + elapsedSeconds * blob.speedY);
      const double driftMultiplier = 1.8;
      final Offset center = Offset(
        size.width * (0.5 + driftMultiplier * nx),
        size.height * (0.5 + driftMultiplier * ny),
      );
      final double radius = blob.sizeFactor * size.width;
      final Rect rect = Rect.fromCircle(center: center, radius: radius);

      final Paint paint = Paint()
        ..shader = RadialGradient(
          colors: <Color>[
            color.withValues(alpha: blob.maxOpacity),
            color.withValues(alpha: 0.0),
          ],
          stops: const <double>[0.0, 1.0],
        ).createShader(rect)
        ..blendMode = BlendMode.screen;

      canvas.drawCircle(center, radius, paint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LavaLampPainter old) =>
      old.elapsedSeconds != elapsedSeconds ||
      old.color != color ||
      old.blobs != blobs;
}
