import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'lumina_palette.dart';

/// Shadow / elevation tokens.
///
/// Dark UIs barely use shadows (they read as smudges); we still expose a few
/// levels so light-mode and modal surfaces can lift off the canvas.
@immutable
class LuminaElevation {
  const LuminaElevation({
    required this.none,
    required this.sm,
    required this.md,
    required this.lg,
  });

  const LuminaElevation.dark()
    : none = const <BoxShadow>[],
      sm = const <BoxShadow>[
        BoxShadow(
          color: Color(0x33000000),
          blurRadius: 8,
          offset: Offset(0, 2),
        ),
      ],
      md = const <BoxShadow>[
        BoxShadow(
          color: Color(0x40000000),
          blurRadius: 16,
          offset: Offset(0, 6),
        ),
      ],
      lg = const <BoxShadow>[
        BoxShadow(
          color: Color(0x59000000),
          blurRadius: 32,
          offset: Offset(0, 16),
        ),
      ];

  LuminaElevation.light()
    : none = const <BoxShadow>[],
      sm = <BoxShadow>[
        BoxShadow(
          color: LuminaPalette.neutral200.withValues(alpha: 0.6),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
      md = <BoxShadow>[
        BoxShadow(
          color: LuminaPalette.neutral300.withValues(alpha: 0.4),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
      lg = <BoxShadow>[
        BoxShadow(
          color: LuminaPalette.neutral400.withValues(alpha: 0.3),
          blurRadius: 32,
          offset: const Offset(0, 16),
        ),
      ];

  final List<BoxShadow> none;
  final List<BoxShadow> sm;
  final List<BoxShadow> md;
  final List<BoxShadow> lg;

  static LuminaElevation lerp(LuminaElevation a, LuminaElevation b, double t) {
    // Shadows aren't trivially lerpable; snap to the target half-way.
    return t < 0.5 ? a : b;
  }
}
