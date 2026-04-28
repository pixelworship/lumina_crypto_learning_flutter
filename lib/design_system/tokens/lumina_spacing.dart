import 'package:flutter/foundation.dart';

/// Spacing scale built on a 4pt grid.
///
/// We use t-shirt sizing because it forces consistency: when designers say
/// "16-pixel gap" they really mean "lg gap", and using semantic names lets us
/// retune the entire app's rhythm without touching widgets.
@immutable
class LuminaSpacing {
  const LuminaSpacing({
    required this.xxs,
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
    required this.xxl,
    required this.xxxl,
    required this.xxxxl,
  });

  /// Default 4pt grid recommended for product surfaces.
  const LuminaSpacing.standard()
    : xxs = 2,
      xs = 4,
      sm = 8,
      md = 12,
      lg = 16,
      xl = 20,
      xxl = 24,
      xxxl = 32,
      xxxxl = 48;

  final double xxs;
  final double xs;
  final double sm;
  final double md;
  final double lg;
  final double xl;
  final double xxl;
  final double xxxl;
  final double xxxxl;

  LuminaSpacing copyWith({
    double? xxs,
    double? xs,
    double? sm,
    double? md,
    double? lg,
    double? xl,
    double? xxl,
    double? xxxl,
    double? xxxxl,
  }) {
    return LuminaSpacing(
      xxs: xxs ?? this.xxs,
      xs: xs ?? this.xs,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      lg: lg ?? this.lg,
      xl: xl ?? this.xl,
      xxl: xxl ?? this.xxl,
      xxxl: xxxl ?? this.xxxl,
      xxxxl: xxxxl ?? this.xxxxl,
    );
  }

  static LuminaSpacing lerp(LuminaSpacing a, LuminaSpacing b, double t) {
    return LuminaSpacing(
      xxs: _lerp(a.xxs, b.xxs, t),
      xs: _lerp(a.xs, b.xs, t),
      sm: _lerp(a.sm, b.sm, t),
      md: _lerp(a.md, b.md, t),
      lg: _lerp(a.lg, b.lg, t),
      xl: _lerp(a.xl, b.xl, t),
      xxl: _lerp(a.xxl, b.xxl, t),
      xxxl: _lerp(a.xxxl, b.xxxl, t),
      xxxxl: _lerp(a.xxxxl, b.xxxxl, t),
    );
  }

  static double _lerp(double a, double b, double t) => a + (b - a) * t;
}
