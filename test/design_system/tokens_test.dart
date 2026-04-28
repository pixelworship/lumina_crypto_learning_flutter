import 'package:flutter/material.dart';
import 'package:flutter_demo/design_system/lumina_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// Build a token bag without touching `google_fonts` so unit tests don't leak
/// async I/O.
LuminaTokens _darkTokens() => LuminaTokens(
  colors: LuminaColorScheme.dark(),
  spacing: const LuminaSpacing.standard(),
  radii: const LuminaRadii.standard(),
  typography: LuminaTypography.system(),
  elevation: const LuminaElevation.dark(),
  motion: const LuminaMotion.standard(),
);

LuminaTokens _lightTokens() => LuminaTokens(
  colors: LuminaColorScheme.light(),
  spacing: const LuminaSpacing.standard(),
  radii: const LuminaRadii.standard(),
  typography: LuminaTypography.system(),
  elevation: LuminaElevation.light(),
  motion: const LuminaMotion.standard(),
);

void main() {
  group('LuminaTokens', () {
    test('exposes distinct dark + light color schemes', () {
      final LuminaTokens dark = _darkTokens();
      final LuminaTokens light = _lightTokens();

      expect(
        dark.colors.surfaceCanvas,
        isNot(equals(light.colors.surfaceCanvas)),
      );
      expect(
        dark.colors.contentPrimary,
        isNot(equals(light.colors.contentPrimary)),
      );
    });

    test('shares brand colors across themes', () {
      final LuminaTokens dark = _darkTokens();
      final LuminaTokens light = _lightTokens();

      expect(dark.colors.brandBtc, equals(light.colors.brandBtc));
      expect(dark.colors.brandEth, equals(light.colors.brandEth));
      expect(dark.colors.brandSol, equals(light.colors.brandSol));
    });

    test('copyWith returns a new instance with selectively overridden fields',
        () {
      final LuminaTokens base = _darkTokens();
      final LuminaTokens overridden = base.copyWith(
        spacing: const LuminaSpacing.standard().copyWith(md: 99),
      );

      expect(overridden.spacing.md, 99);
      expect(overridden.colors, equals(base.colors));
    });

    test('lerp at t=0 returns the start tokens', () {
      final LuminaTokens dark = _darkTokens();
      final LuminaTokens light = _lightTokens();

      final LuminaTokens lerped = dark.lerp(light, 0);

      expect(lerped.colors.surfaceCanvas, equals(dark.colors.surfaceCanvas));
    });

    test('lerp at t=1 returns the end tokens', () {
      final LuminaTokens dark = _darkTokens();
      final LuminaTokens light = _lightTokens();

      final LuminaTokens lerped = dark.lerp(light, 1);

      expect(lerped.colors.surfaceCanvas, equals(light.colors.surfaceCanvas));
    });

    test('lerp at t=0.5 produces an interpolated color', () {
      final LuminaTokens dark = _darkTokens();
      final LuminaTokens light = _lightTokens();
      final LuminaTokens lerped = dark.lerp(light, 0.5);

      final Color expected = Color.lerp(
        dark.colors.surfaceCanvas,
        light.colors.surfaceCanvas,
        0.5,
      )!;
      expect(lerped.colors.surfaceCanvas, equals(expected));
    });

    test('LuminaSpacing.lerp interpolates spacing tokens', () {
      const LuminaSpacing a = LuminaSpacing.standard();
      final LuminaSpacing b = a.copyWith(md: a.md + 10);

      final LuminaSpacing mid = LuminaSpacing.lerp(a, b, 0.5);

      expect(mid.md, equals(a.md + 5));
    });
  });

  group('context.tokens', () {
    testWidgets('resolves the LuminaTokens attached to ThemeData', (
      WidgetTester tester,
    ) async {
      LuminaTokens? captured;
      await tester.pumpWidget(
        MaterialApp(
          theme: LuminaTheme.dark(),
          home: Builder(
            builder: (BuildContext ctx) {
              captured = ctx.tokens;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(captured, isNotNull);
      // Surface color must come from the dark scheme.
      expect(
        captured!.colors.surfaceCanvas,
        equals(LuminaColorScheme.dark().surfaceCanvas),
      );
    });

    testWidgets('falls back to dark tokens when no theme extension is present',
        (WidgetTester tester) async {
      LuminaTokens? captured;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext ctx) {
              captured = ctx.tokens;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(captured, isNotNull);
      expect(
        captured!.colors.surfaceCanvas,
        equals(LuminaColorScheme.dark().surfaceCanvas),
      );
    });
  });
}
