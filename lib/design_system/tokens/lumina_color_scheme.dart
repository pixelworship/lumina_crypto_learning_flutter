import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'lumina_palette.dart';

/// Semantic color scheme.
///
/// Every color a widget should ever read at runtime lives here, keyed by
/// *intent* rather than *value*. This is what enables a single light-mode
/// switch to retheme the entire app — widgets never hard-code primitives.
///
/// The naming convention is `<role>.<variant>`:
///   * `surface*` - backgrounds (canvas, cards, modals)
///   * `content*` - foregrounds (text, icons)
///   * `border*` - strokes
///   * `accent*` - brand / interactive
///   * `feedback*` - success/danger/warning/info
///   * `chart*` - dataviz
///   * `brand*` - third-party crypto brand colors (constant across themes)
@immutable
class LuminaColorScheme {
  const LuminaColorScheme({
    required this.surfaceCanvas,
    required this.surfaceRaised,
    required this.surfaceSunken,
    required this.surfaceMuted,
    required this.surfaceInverse,
    required this.scrim,
    required this.contentPrimary,
    required this.contentSecondary,
    required this.contentTertiary,
    required this.contentDisabled,
    required this.contentInverse,
    required this.borderSubtle,
    required this.borderDefault,
    required this.borderStrong,
    required this.accentPrimary,
    required this.accentPrimaryHover,
    required this.accentPrimaryPressed,
    required this.onAccentPrimary,
    required this.accentSecondary,
    required this.feedbackPositive,
    required this.feedbackPositiveSurface,
    required this.feedbackNegative,
    required this.feedbackNegativeSurface,
    required this.feedbackWarning,
    required this.feedbackWarningSurface,
    required this.feedbackInfo,
    required this.chartLine,
    required this.chartGrid,
    required this.chartFillTop,
    required this.chartFillBottom,
    required this.brandBtc,
    required this.brandEth,
    required this.brandSol,
    required this.brandUni,
    required this.brandAda,
    required this.brandUsdt,
    required this.brandAvax,
    required this.brandAxs,
    required this.brandSand,
  });

  // ---------------------------------------------------------------------------
  // Dark mode (default for Lumina).
  // ---------------------------------------------------------------------------
  factory LuminaColorScheme.dark() {
    return const LuminaColorScheme(
      surfaceCanvas: LuminaPalette.indigo950,
      surfaceRaised: LuminaPalette.indigo800,
      surfaceSunken: LuminaPalette.indigo900,
      surfaceMuted: LuminaPalette.indigo700,
      surfaceInverse: LuminaPalette.neutral50,
      scrim: Color(0xCC000000),
      contentPrimary: LuminaPalette.neutral50,
      contentSecondary: LuminaPalette.neutral300,
      contentTertiary: LuminaPalette.neutral500,
      contentDisabled: LuminaPalette.neutral600,
      contentInverse: LuminaPalette.indigo950,
      borderSubtle: LuminaPalette.indigo700,
      borderDefault: LuminaPalette.indigo600,
      borderStrong: LuminaPalette.indigo500,
      accentPrimary: LuminaPalette.cyan400,
      accentPrimaryHover: LuminaPalette.cyan300,
      accentPrimaryPressed: LuminaPalette.cyan500,
      onAccentPrimary: LuminaPalette.cyan900,
      accentSecondary: LuminaPalette.violet500,
      feedbackPositive: LuminaPalette.emerald300,
      feedbackPositiveSurface: Color(0x336EE7B7),
      feedbackNegative: LuminaPalette.rose400,
      feedbackNegativeSurface: Color(0x33F87171),
      feedbackWarning: LuminaPalette.amber400,
      feedbackWarningSurface: Color(0x33FBBF24),
      feedbackInfo: LuminaPalette.cyan300,
      chartLine: LuminaPalette.cyan400,
      chartGrid: LuminaPalette.indigo600,
      chartFillTop: Color(0x552DE3D2),
      chartFillBottom: Color.fromARGB(0, 39, 211, 193),
      brandBtc: LuminaPalette.brandBtc,
      brandEth: LuminaPalette.brandEth,
      brandSol: LuminaPalette.brandSol,
      brandUni: LuminaPalette.brandUni,
      brandAda: LuminaPalette.brandAda,
      brandUsdt: LuminaPalette.brandUsdt,
      brandAvax: LuminaPalette.brandAvax,
      brandAxs: LuminaPalette.brandAxs,
      brandSand: LuminaPalette.brandSand,
    );
  }

  // ---------------------------------------------------------------------------
  // Light mode - a properly-tuned counterpart so the architecture is real,
  // not aspirational. Designers can adopt this without re-deriving everything.
  // ---------------------------------------------------------------------------
  factory LuminaColorScheme.light() {
    return const LuminaColorScheme(
      surfaceCanvas: LuminaPalette.neutral50,
      surfaceRaised: LuminaPalette.neutral0,
      surfaceSunken: LuminaPalette.neutral100,
      surfaceMuted: LuminaPalette.neutral100,
      surfaceInverse: LuminaPalette.indigo900,
      scrim: Color(0x80000000),
      contentPrimary: LuminaPalette.indigo900,
      contentSecondary: LuminaPalette.neutral600,
      contentTertiary: LuminaPalette.neutral500,
      contentDisabled: LuminaPalette.neutral300,
      contentInverse: LuminaPalette.neutral50,
      borderSubtle: LuminaPalette.neutral100,
      borderDefault: LuminaPalette.neutral200,
      borderStrong: LuminaPalette.neutral300,
      accentPrimary: LuminaPalette.cyan500,
      accentPrimaryHover: LuminaPalette.cyan400,
      accentPrimaryPressed: LuminaPalette.cyan600,
      onAccentPrimary: LuminaPalette.cyan900,
      accentSecondary: LuminaPalette.violet600,
      feedbackPositive: LuminaPalette.emerald600,
      feedbackPositiveSurface: LuminaPalette.emerald50,
      feedbackNegative: LuminaPalette.rose600,
      feedbackNegativeSurface: LuminaPalette.rose50,
      feedbackWarning: LuminaPalette.amber600,
      feedbackWarningSurface: LuminaPalette.amber50,
      feedbackInfo: LuminaPalette.cyan600,
      chartLine: LuminaPalette.cyan500,
      chartGrid: LuminaPalette.neutral200,
      chartFillTop: Color(0x4015B5A6),
      chartFillBottom: Color(0x0015B5A6),
      brandBtc: LuminaPalette.brandBtc,
      brandEth: LuminaPalette.brandEth,
      brandSol: LuminaPalette.brandSol,
      brandUni: LuminaPalette.brandUni,
      brandAda: LuminaPalette.brandAda,
      brandUsdt: LuminaPalette.brandUsdt,
      brandAvax: LuminaPalette.brandAvax,
      brandAxs: LuminaPalette.brandAxs,
      brandSand: LuminaPalette.brandSand,
    );
  }

  final Color surfaceCanvas;
  final Color surfaceRaised;
  final Color surfaceSunken;
  final Color surfaceMuted;
  final Color surfaceInverse;
  final Color scrim;

  final Color contentPrimary;
  final Color contentSecondary;
  final Color contentTertiary;
  final Color contentDisabled;
  final Color contentInverse;

  final Color borderSubtle;
  final Color borderDefault;
  final Color borderStrong;

  final Color accentPrimary;
  final Color accentPrimaryHover;
  final Color accentPrimaryPressed;
  final Color onAccentPrimary;
  final Color accentSecondary;

  final Color feedbackPositive;
  final Color feedbackPositiveSurface;
  final Color feedbackNegative;
  final Color feedbackNegativeSurface;
  final Color feedbackWarning;
  final Color feedbackWarningSurface;
  final Color feedbackInfo;

  final Color chartLine;
  final Color chartGrid;
  final Color chartFillTop;
  final Color chartFillBottom;

  // Brand colors stay constant across themes.
  final Color brandBtc;
  final Color brandEth;
  final Color brandSol;
  final Color brandUni;
  final Color brandAda;
  final Color brandUsdt;
  final Color brandAvax;
  final Color brandAxs;
  final Color brandSand;

  /// Convenience gradient used behind balance hero cards.
  LinearGradient get heroGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: <Color>[surfaceRaised, surfaceSunken],
  );

  /// Gradient used to fade the price area chart toward the canvas.
  LinearGradient get chartFillGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[chartFillTop, chartFillBottom],
  );

  static LuminaColorScheme lerp(
    LuminaColorScheme a,
    LuminaColorScheme b,
    double t,
  ) {
    Color l(Color x, Color y) => Color.lerp(x, y, t)!;
    return LuminaColorScheme(
      surfaceCanvas: l(a.surfaceCanvas, b.surfaceCanvas),
      surfaceRaised: l(a.surfaceRaised, b.surfaceRaised),
      surfaceSunken: l(a.surfaceSunken, b.surfaceSunken),
      surfaceMuted: l(a.surfaceMuted, b.surfaceMuted),
      surfaceInverse: l(a.surfaceInverse, b.surfaceInverse),
      scrim: l(a.scrim, b.scrim),
      contentPrimary: l(a.contentPrimary, b.contentPrimary),
      contentSecondary: l(a.contentSecondary, b.contentSecondary),
      contentTertiary: l(a.contentTertiary, b.contentTertiary),
      contentDisabled: l(a.contentDisabled, b.contentDisabled),
      contentInverse: l(a.contentInverse, b.contentInverse),
      borderSubtle: l(a.borderSubtle, b.borderSubtle),
      borderDefault: l(a.borderDefault, b.borderDefault),
      borderStrong: l(a.borderStrong, b.borderStrong),
      accentPrimary: l(a.accentPrimary, b.accentPrimary),
      accentPrimaryHover: l(a.accentPrimaryHover, b.accentPrimaryHover),
      accentPrimaryPressed: l(a.accentPrimaryPressed, b.accentPrimaryPressed),
      onAccentPrimary: l(a.onAccentPrimary, b.onAccentPrimary),
      accentSecondary: l(a.accentSecondary, b.accentSecondary),
      feedbackPositive: l(a.feedbackPositive, b.feedbackPositive),
      feedbackPositiveSurface: l(
        a.feedbackPositiveSurface,
        b.feedbackPositiveSurface,
      ),
      feedbackNegative: l(a.feedbackNegative, b.feedbackNegative),
      feedbackNegativeSurface: l(
        a.feedbackNegativeSurface,
        b.feedbackNegativeSurface,
      ),
      feedbackWarning: l(a.feedbackWarning, b.feedbackWarning),
      feedbackWarningSurface: l(
        a.feedbackWarningSurface,
        b.feedbackWarningSurface,
      ),
      feedbackInfo: l(a.feedbackInfo, b.feedbackInfo),
      chartLine: l(a.chartLine, b.chartLine),
      chartGrid: l(a.chartGrid, b.chartGrid),
      chartFillTop: l(a.chartFillTop, b.chartFillTop),
      chartFillBottom: l(a.chartFillBottom, b.chartFillBottom),
      brandBtc: a.brandBtc,
      brandEth: a.brandEth,
      brandSol: a.brandSol,
      brandUni: a.brandUni,
      brandAda: a.brandAda,
      brandUsdt: a.brandUsdt,
      brandAvax: a.brandAvax,
      brandAxs: a.brandAxs,
      brandSand: a.brandSand,
    );
  }
}
