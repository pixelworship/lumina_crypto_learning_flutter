import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Border radius scale.
@immutable
class LuminaRadii {
  const LuminaRadii({
    required this.none,
    required this.xs,
    required this.sm,
    required this.md,
    required this.lg,
    required this.xl,
    required this.xxl,
    required this.full,
  });

  const LuminaRadii.standard()
    : none = const Radius.circular(0),
      xs = const Radius.circular(4),
      sm = const Radius.circular(8),
      md = const Radius.circular(12),
      lg = const Radius.circular(16),
      xl = const Radius.circular(20),
      xxl = const Radius.circular(24),
      full = const Radius.circular(999);

  final Radius none;
  final Radius xs;
  final Radius sm;
  final Radius md;
  final Radius lg;
  final Radius xl;
  final Radius xxl;
  final Radius full;

  /// Convenience: matching [BorderRadius.all] helpers used everywhere widgets
  /// need a uniform radius.
  BorderRadius get xsAll => BorderRadius.all(xs);
  BorderRadius get smAll => BorderRadius.all(sm);
  BorderRadius get mdAll => BorderRadius.all(md);
  BorderRadius get lgAll => BorderRadius.all(lg);
  BorderRadius get xlAll => BorderRadius.all(xl);
  BorderRadius get xxlAll => BorderRadius.all(xxl);
  BorderRadius get pillAll => BorderRadius.all(full);

  static LuminaRadii lerp(LuminaRadii a, LuminaRadii b, double t) {
    return LuminaRadii(
      none: Radius.lerp(a.none, b.none, t)!,
      xs: Radius.lerp(a.xs, b.xs, t)!,
      sm: Radius.lerp(a.sm, b.sm, t)!,
      md: Radius.lerp(a.md, b.md, t)!,
      lg: Radius.lerp(a.lg, b.lg, t)!,
      xl: Radius.lerp(a.xl, b.xl, t)!,
      xxl: Radius.lerp(a.xxl, b.xxl, t)!,
      full: Radius.lerp(a.full, b.full, t)!,
    );
  }
}
