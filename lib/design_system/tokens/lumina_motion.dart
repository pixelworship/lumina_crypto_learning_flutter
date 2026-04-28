import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

/// Duration + easing tokens used by every animated component.
///
/// Centralizing these is what stops a codebase from accumulating dozens of
/// subtly different `Duration(milliseconds: 270)`s.
@immutable
class LuminaMotion {
  const LuminaMotion({
    required this.fast,
    required this.medium,
    required this.slow,
    required this.standardEase,
    required this.emphasizedEase,
    required this.decelerateEase,
  });

  const LuminaMotion.standard()
    : fast = const Duration(milliseconds: 150),
      medium = const Duration(milliseconds: 250),
      slow = const Duration(milliseconds: 350),
      standardEase = Curves.easeInOut,
      emphasizedEase = Curves.easeOutCubic,
      decelerateEase = Curves.decelerate;

  final Duration fast;
  final Duration medium;
  final Duration slow;
  final Curve standardEase;
  final Curve emphasizedEase;
  final Curve decelerateEase;

  static LuminaMotion lerp(LuminaMotion a, LuminaMotion b, double t) {
    return t < 0.5 ? a : b;
  }
}
