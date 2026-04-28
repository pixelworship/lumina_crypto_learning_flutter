import 'package:flutter/material.dart';

import 'lumina_color_scheme.dart';
import 'lumina_elevation.dart';
import 'lumina_motion.dart';
import 'lumina_radii.dart';
import 'lumina_spacing.dart';
import 'lumina_typography.dart';

/// Aggregate design token bag exposed via [ThemeExtension].
///
/// Every Lumina widget reads tokens through `context.tokens`, which resolves
/// to the [LuminaTokens] instance attached to the current [Theme]. This is
/// what makes light/dark switching one `MaterialApp.themeMode` change away.
///
/// To access tokens in a widget:
/// ```dart
/// final tokens = context.tokens;
/// Container(
///   padding: EdgeInsets.all(tokens.spacing.md),
///   color: tokens.colors.surfaceRaised,
///   child: Text('Hello', style: tokens.typography.titleMd),
/// )
/// ```
@immutable
class LuminaTokens extends ThemeExtension<LuminaTokens> {
  const LuminaTokens({
    required this.colors,
    required this.spacing,
    required this.radii,
    required this.typography,
    required this.elevation,
    required this.motion,
  });

  /// Default dark-mode tokens used by Lumina.
  factory LuminaTokens.dark() => LuminaTokens(
    colors: LuminaColorScheme.dark(),
    spacing: const LuminaSpacing.standard(),
    radii: const LuminaRadii.standard(),
    typography: LuminaTypography.standard(),
    elevation: const LuminaElevation.dark(),
    motion: const LuminaMotion.standard(),
  );

  factory LuminaTokens.light() => LuminaTokens(
    colors: LuminaColorScheme.light(),
    spacing: const LuminaSpacing.standard(),
    radii: const LuminaRadii.standard(),
    typography: LuminaTypography.standard(),
    elevation: LuminaElevation.light(),
    motion: const LuminaMotion.standard(),
  );

  final LuminaColorScheme colors;
  final LuminaSpacing spacing;
  final LuminaRadii radii;
  final LuminaTypography typography;
  final LuminaElevation elevation;
  final LuminaMotion motion;

  @override
  LuminaTokens copyWith({
    LuminaColorScheme? colors,
    LuminaSpacing? spacing,
    LuminaRadii? radii,
    LuminaTypography? typography,
    LuminaElevation? elevation,
    LuminaMotion? motion,
  }) {
    return LuminaTokens(
      colors: colors ?? this.colors,
      spacing: spacing ?? this.spacing,
      radii: radii ?? this.radii,
      typography: typography ?? this.typography,
      elevation: elevation ?? this.elevation,
      motion: motion ?? this.motion,
    );
  }

  @override
  LuminaTokens lerp(ThemeExtension<LuminaTokens>? other, double t) {
    if (other is! LuminaTokens) return this;
    return LuminaTokens(
      colors: LuminaColorScheme.lerp(colors, other.colors, t),
      spacing: LuminaSpacing.lerp(spacing, other.spacing, t),
      radii: LuminaRadii.lerp(radii, other.radii, t),
      typography: LuminaTypography.lerp(typography, other.typography, t),
      elevation: LuminaElevation.lerp(elevation, other.elevation, t),
      motion: LuminaMotion.lerp(motion, other.motion, t),
    );
  }
}

/// Ergonomic accessor for the active [LuminaTokens].
///
/// Falls back to dark tokens if a widget is rendered without a theme — this
/// keeps tests, previews, and orphaned widgets from crashing.
extension LuminaTokensX on BuildContext {
  LuminaTokens get tokens =>
      Theme.of(this).extension<LuminaTokens>() ?? LuminaTokens.dark();
}
