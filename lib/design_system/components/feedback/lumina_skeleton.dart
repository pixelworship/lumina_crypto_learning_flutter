import 'package:flutter/material.dart';

import '../../tokens/lumina_tokens.dart';

/// Animated shimmer placeholder used while real content is loading.
class LuminaSkeleton extends StatefulWidget {
  const LuminaSkeleton({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius,
  });

  /// Convenience: a circular skeleton (e.g. avatar placeholder).
  const LuminaSkeleton.circle({super.key, required double size})
    : width = size,
      height = size,
      borderRadius = const BorderRadius.all(Radius.circular(999));

  final double? width;
  final double height;
  final BorderRadius? borderRadius;

  @override
  State<LuminaSkeleton> createState() => _LuminaSkeletonState();
}

class _LuminaSkeletonState extends State<LuminaSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius ?? t.radii.smAll,
            gradient: LinearGradient(
              begin: Alignment(-1.0 + 2 * _controller.value, 0),
              end: Alignment(1.0 + 2 * _controller.value, 0),
              colors: <Color>[
                t.colors.surfaceRaised,
                t.colors.surfaceMuted,
                t.colors.surfaceRaised,
              ],
              stops: const <double>[0.1, 0.5, 0.9],
            ),
          ),
        );
      },
    );
  }
}
