/// Lumina UI — public API surface for the Lumina design system.
///
/// Importing this file exposes:
///   * Token primitives (palette, spacing, radii, typography, motion, elevation)
///   * Semantic [LuminaColorScheme] + aggregate [LuminaTokens] ThemeExtension
///   * The `context.tokens` extension for ergonomic access
///   * [LuminaTheme] factories for [ThemeData] (dark + light)
///   * [ThemeModeCubit] for runtime theme switching
///   * Every Lumina* component
///
/// Code outside `design_system/` should import only this file.
library;

// Tokens
export 'tokens/lumina_color_scheme.dart';
export 'tokens/lumina_elevation.dart';
export 'tokens/lumina_motion.dart';
export 'tokens/lumina_palette.dart';
export 'tokens/lumina_radii.dart';
export 'tokens/lumina_spacing.dart';
export 'tokens/lumina_tokens.dart';
export 'tokens/lumina_typography.dart';

// Theme
export 'theme/lumina_theme.dart';
export 'theme/theme_mode_cubit.dart';

// Components
export 'components/avatars/lumina_avatar.dart';
export 'components/buttons/lumina_button.dart';
export 'components/buttons/lumina_icon_button.dart';
export 'components/cards/lumina_card.dart';
export 'components/chips/lumina_chip.dart';
export 'components/controls/lumina_segmented_control.dart';
export 'components/feedback/lumina_change_pill.dart';
export 'components/feedback/lumina_delta.dart';
export 'components/feedback/lumina_empty_state.dart';
export 'components/feedback/lumina_error_view.dart';
export 'components/feedback/lumina_loading_indicator.dart';
export 'components/feedback/lumina_numeric_text.dart';
export 'components/feedback/lumina_skeleton.dart';
export 'components/inputs/lumina_text_field.dart';
export 'components/layout/lumina_badge.dart';
export 'components/layout/lumina_list_tile.dart';
export 'components/layout/lumina_section_header.dart';
