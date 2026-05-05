import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography scale.
///
/// Each style is a fully-formed [TextStyle] (sans color — color comes from the
/// semantic palette). Scales map to roles, not pixel sizes, so designers can
/// retune the hierarchy without grepping the codebase.
@immutable
class LuminaTypography {
  const LuminaTypography({
    required this.displayLg,
    required this.displayMd,
    required this.titleLg,
    required this.titleMd,
    required this.titleSm,
    required this.bodyLg,
    required this.bodyMd,
    required this.bodySm,
    required this.labelLg,
    required this.labelMd,
    required this.labelSm,
    required this.numericLg,
    required this.numericMd,
    required this.numericSm,
  });

  /// Inter for prose; JetBrains Mono for everything numeric.
  ///
  /// Numeric variants use a true monospace face (JetBrains Mono) so
  /// every glyph in a price — digits, decimals, commas, currency
  /// symbol, percent — has identical advance width. That means
  /// `$10,234.56` and `$10,234.57` paint to the exact same pixel
  /// positions and the value can flicker through ticks without the
  /// surrounding row shifting. `tabularFigures` is layered on top
  /// as a belt-and-suspenders measure for mid-tick fallback faces.
  ///
  /// Pass [baseStyle] / [baseNumericStyle] in tests or previews to
  /// skip `google_fonts` HTTP/cache I/O.
  factory LuminaTypography.standard({
    TextStyle? baseStyle,
    TextStyle? baseNumericStyle,
  }) {
    final TextStyle base = baseStyle ?? GoogleFonts.inter();
    final TextStyle baseNum = baseNumericStyle ??
        GoogleFonts.jetBrainsMono(
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        );

    return LuminaTypography(
      displayLg: base.copyWith(fontSize: 32, fontWeight: FontWeight.w700, height: 1.1),
      displayMd: base.copyWith(fontSize: 28, fontWeight: FontWeight.w700, height: 1.15),
      titleLg: base.copyWith(fontSize: 22, fontWeight: FontWeight.w700, height: 1.2),
      titleMd: base.copyWith(fontSize: 18, fontWeight: FontWeight.w700, height: 1.25),
      titleSm: base.copyWith(fontSize: 15, fontWeight: FontWeight.w600, height: 1.3),
      bodyLg: base.copyWith(fontSize: 16, fontWeight: FontWeight.w500, height: 1.45),
      bodyMd: base.copyWith(fontSize: 14, fontWeight: FontWeight.w500, height: 1.45),
      bodySm: base.copyWith(fontSize: 12, fontWeight: FontWeight.w500, height: 1.45),
      labelLg: base.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
        height: 1.2,
      ),
      labelMd: base.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        height: 1.2,
      ),
      labelSm: base.copyWith(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        height: 1.2,
      ),
      numericLg: baseNum.copyWith(fontSize: 30, fontWeight: FontWeight.w700, height: 1.1),
      numericMd: baseNum.copyWith(fontSize: 18, fontWeight: FontWeight.w700, height: 1.2),
      numericSm: baseNum.copyWith(fontSize: 13, fontWeight: FontWeight.w600, height: 1.3),
    );
  }

  /// Test/preview-friendly typography that uses the platform default
  /// fonts (no HTTP / disk I/O). The numeric variant points at the
  /// generic `'monospace'` family so layout-sensitive widget tests
  /// still get equal-width digit advances; production paints with
  /// JetBrains Mono via [LuminaTypography.standard]. Use this in
  /// unit tests that construct tokens directly without a
  /// [WidgetTester].
  factory LuminaTypography.system() => LuminaTypography.standard(
    baseStyle: const TextStyle(),
    baseNumericStyle: const TextStyle(
      fontFamily: 'monospace',
      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
    ),
  );

  final TextStyle displayLg;
  final TextStyle displayMd;
  final TextStyle titleLg;
  final TextStyle titleMd;
  final TextStyle titleSm;
  final TextStyle bodyLg;
  final TextStyle bodyMd;
  final TextStyle bodySm;
  final TextStyle labelLg;
  final TextStyle labelMd;
  final TextStyle labelSm;
  final TextStyle numericLg;
  final TextStyle numericMd;
  final TextStyle numericSm;

  static LuminaTypography lerp(
    LuminaTypography a,
    LuminaTypography b,
    double t,
  ) {
    return LuminaTypography(
      displayLg: TextStyle.lerp(a.displayLg, b.displayLg, t)!,
      displayMd: TextStyle.lerp(a.displayMd, b.displayMd, t)!,
      titleLg: TextStyle.lerp(a.titleLg, b.titleLg, t)!,
      titleMd: TextStyle.lerp(a.titleMd, b.titleMd, t)!,
      titleSm: TextStyle.lerp(a.titleSm, b.titleSm, t)!,
      bodyLg: TextStyle.lerp(a.bodyLg, b.bodyLg, t)!,
      bodyMd: TextStyle.lerp(a.bodyMd, b.bodyMd, t)!,
      bodySm: TextStyle.lerp(a.bodySm, b.bodySm, t)!,
      labelLg: TextStyle.lerp(a.labelLg, b.labelLg, t)!,
      labelMd: TextStyle.lerp(a.labelMd, b.labelMd, t)!,
      labelSm: TextStyle.lerp(a.labelSm, b.labelSm, t)!,
      numericLg: TextStyle.lerp(a.numericLg, b.numericLg, t)!,
      numericMd: TextStyle.lerp(a.numericMd, b.numericMd, t)!,
      numericSm: TextStyle.lerp(a.numericSm, b.numericSm, t)!,
    );
  }
}
