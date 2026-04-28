import 'package:flutter/painting.dart';

/// Reference (primitive) color palettes.
///
/// These are the raw, named color values that make up the Lumina brand. They
/// are intentionally unopinionated about *intent* — semantic meaning belongs in
/// [LuminaColorScheme] which composes these primitives into roles like
/// `surface`, `accent`, `feedback.success`, etc.
///
/// Designers and engineers should rarely reach into this file directly:
/// production widgets should consume semantic tokens via `context.tokens`.
class LuminaPalette {
  const LuminaPalette._();

  // ---------------------------------------------------------------------------
  // Indigo - the deep navy backdrop of Lumina's dark mode.
  // ---------------------------------------------------------------------------
  static const Color indigo50 = Color(0xFFEDEAFB);
  static const Color indigo100 = Color(0xFFD3CBF3);
  static const Color indigo200 = Color(0xFFA89AE6);
  static const Color indigo300 = Color(0xFF7E69D9);
  static const Color indigo400 = Color(0xFF5544AC);
  static const Color indigo500 = Color(0xFF362A82);
  static const Color indigo600 = Color(0xFF2A2150);
  static const Color indigo700 = Color(0xFF221A45);
  static const Color indigo800 = Color(0xFF1A1438);
  static const Color indigo850 = Color(0xFF15102E);
  static const Color indigo900 = Color(0xFF120D2E);
  static const Color indigo950 = Color(0xFF0B0820);

  // ---------------------------------------------------------------------------
  // Cyan - primary accent (CTAs, charts, active states).
  // ---------------------------------------------------------------------------
  static const Color cyan50 = Color(0xFFE6FBF8);
  static const Color cyan100 = Color(0xFFB6F4ED);
  static const Color cyan200 = Color(0xFF7FEAE0);
  static const Color cyan300 = Color(0xFF4EE0D2);
  static const Color cyan400 = Color(0xFF2DE3D2);
  static const Color cyan500 = Color(0xFF15B5A6);
  static const Color cyan600 = Color(0xFF0F8C81);
  static const Color cyan700 = Color(0xFF0A6961);
  static const Color cyan800 = Color(0xFF064540);
  static const Color cyan900 = Color(0xFF052622);

  // ---------------------------------------------------------------------------
  // Emerald - success / positive change.
  // ---------------------------------------------------------------------------
  static const Color emerald50 = Color(0xFFEAFBF1);
  static const Color emerald100 = Color(0xFFC4F4D9);
  static const Color emerald200 = Color(0xFF8FE9B7);
  static const Color emerald300 = Color(0xFF6EE7B7);
  static const Color emerald400 = Color(0xFF34D399);
  static const Color emerald500 = Color(0xFF10B981);
  static const Color emerald600 = Color(0xFF059669);
  static const Color emerald700 = Color(0xFF047857);
  static const Color emerald800 = Color(0xFF065F46);
  static const Color emerald900 = Color(0xFF064E3B);

  // ---------------------------------------------------------------------------
  // Rose - danger / negative change.
  // ---------------------------------------------------------------------------
  static const Color rose50 = Color(0xFFFFF1F2);
  static const Color rose100 = Color(0xFFFFE4E6);
  static const Color rose200 = Color(0xFFFECDD3);
  static const Color rose300 = Color(0xFFFDA4AF);
  static const Color rose400 = Color(0xFFF87171);
  static const Color rose500 = Color(0xFFEF4444);
  static const Color rose600 = Color(0xFFDC2626);
  static const Color rose700 = Color(0xFFB91C1C);
  static const Color rose800 = Color(0xFF991B1B);
  static const Color rose900 = Color(0xFF7F1D1D);

  // ---------------------------------------------------------------------------
  // Amber - warning / pending states.
  // ---------------------------------------------------------------------------
  static const Color amber50 = Color(0xFFFFFBEB);
  static const Color amber200 = Color(0xFFFDE68A);
  static const Color amber400 = Color(0xFFFBBF24);
  static const Color amber500 = Color(0xFFFACC15);
  static const Color amber600 = Color(0xFFD97706);
  static const Color amber700 = Color(0xFFB45309);

  // ---------------------------------------------------------------------------
  // Violet - secondary brand accent.
  // ---------------------------------------------------------------------------
  static const Color violet50 = Color(0xFFF3F0FF);
  static const Color violet300 = Color(0xFFC4B5FD);
  static const Color violet400 = Color(0xFFA78BFA);
  static const Color violet500 = Color(0xFF8B5CF6);
  static const Color violet600 = Color(0xFF7C3AED);
  static const Color violet700 = Color(0xFF6D28D9);

  // ---------------------------------------------------------------------------
  // Neutral - text, borders, dividers (cool-toned to harmonize with indigo).
  // ---------------------------------------------------------------------------
  static const Color neutral0 = Color(0xFFFFFFFF);
  static const Color neutral50 = Color(0xFFF5F3FF);
  static const Color neutral100 = Color(0xFFE8E5F4);
  static const Color neutral200 = Color(0xFFCFC9E5);
  static const Color neutral300 = Color(0xFFB8B1D9);
  static const Color neutral400 = Color(0xFF9D94C5);
  static const Color neutral500 = Color(0xFF7A6FA8);
  static const Color neutral600 = Color(0xFF584F82);
  static const Color neutral700 = Color(0xFF3F3863);
  static const Color neutral800 = Color(0xFF2A2150);
  static const Color neutral900 = Color(0xFF15102E);
  static const Color neutral1000 = Color(0xFF000000);

  // ---------------------------------------------------------------------------
  // Brand colors for crypto assets.
  //
  // These are mapped 1:1 to public-facing brand identities (Bitcoin orange,
  // Ethereum blue, etc.) and should never be remapped per-theme.
  // ---------------------------------------------------------------------------
  static const Color brandBtc = Color.fromARGB(255, 26, 203, 247);
  static const Color brandEth = Color(0xFF627EEA);
  static const Color brandSol = Color(0xFFB561F6);
  static const Color brandUni = Color(0xFFFF007A);
  static const Color brandAda = Color(0xFFEF4444);
  static const Color brandUsdt = Color(0xFF26A17B);
  static const Color brandAvax = Color(0xFFE84142);
  static const Color brandAxs = Color(0xFF0055D5);
  static const Color brandSand = Color(0xFF00ADEF);
}
