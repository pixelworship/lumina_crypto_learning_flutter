import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens/lumina_tokens.dart';

/// Builds Material [ThemeData] hooked up to [LuminaTokens].
///
/// We hand-tune Material's component themes so that the few places we *do*
/// use raw Material widgets (SnackBar, RefreshIndicator, etc.) match our
/// design system without requiring custom wrappers everywhere.
class LuminaTheme {
  LuminaTheme._();

  static ThemeData dark() => _buildTheme(LuminaTokens.dark(), Brightness.dark);

  static ThemeData light() =>
      _buildTheme(LuminaTokens.light(), Brightness.light);

  static ThemeData _buildTheme(LuminaTokens tokens, Brightness brightness) {
    final TextTheme textTheme = TextTheme(
      displayLarge: tokens.typography.displayLg,
      displayMedium: tokens.typography.displayMd,
      titleLarge: tokens.typography.titleLg,
      titleMedium: tokens.typography.titleMd,
      titleSmall: tokens.typography.titleSm,
      bodyLarge: tokens.typography.bodyLg,
      bodyMedium: tokens.typography.bodyMd,
      bodySmall: tokens.typography.bodySm,
      labelLarge: tokens.typography.labelLg,
      labelMedium: tokens.typography.labelMd,
      labelSmall: tokens.typography.labelSm,
    ).apply(
      bodyColor: tokens.colors.contentPrimary,
      displayColor: tokens.colors.contentPrimary,
    );

    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      scaffoldBackgroundColor: tokens.colors.surfaceCanvas,
      canvasColor: tokens.colors.surfaceCanvas,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: tokens.colors.accentPrimary,
        onPrimary: tokens.colors.onAccentPrimary,
        secondary: tokens.colors.accentSecondary,
        onSecondary: tokens.colors.contentPrimary,
        surface: tokens.colors.surfaceRaised,
        onSurface: tokens.colors.contentPrimary,
        error: tokens.colors.feedbackNegative,
        onError: tokens.colors.contentPrimary,
      ),
      textTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[tokens],
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.colors.surfaceCanvas,
        elevation: 0,
        centerTitle: true,
        scrolledUnderElevation: 0,
        systemOverlayStyle: brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        titleTextStyle: tokens.typography.titleSm.copyWith(
          color: tokens.colors.contentPrimary,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: tokens.colors.borderSubtle,
        thickness: 1,
        space: 1,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: tokens.colors.surfaceRaised,
        selectedItemColor: tokens.colors.accentPrimary,
        unselectedItemColor: tokens.colors.contentTertiary,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: tokens.colors.accentPrimary,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: tokens.colors.surfaceRaised,
        contentTextStyle: tokens.typography.bodyMd.copyWith(
          color: tokens.colors.contentPrimary,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: tokens.radii.lgAll),
      ),
      splashFactory: InkSparkle.splashFactory,
    );
  }
}
