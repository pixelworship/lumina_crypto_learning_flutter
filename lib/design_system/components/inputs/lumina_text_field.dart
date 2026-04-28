import 'package:flutter/material.dart';

import '../../tokens/lumina_tokens.dart';

/// Themed text field. Use [LuminaTextField.search] for search inputs.
class LuminaTextField extends StatelessWidget {
  const LuminaTextField({
    super.key,
    this.controller,
    this.label,
    this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.prefixIcon,
    this.suffixIcon,
    this.suffixText,
    this.keyboardType,
    this.textInputAction,
    this.autofocus = false,
    this.enabled = true,
  });

  /// Pre-styled search variant: rounded, magnifier prefix.
  const LuminaTextField.search({
    super.key,
    this.controller,
    this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
  }) : label = null,
       prefixIcon = Icons.search_rounded,
       suffixIcon = null,
       suffixText = null,
       keyboardType = null,
       textInputAction = TextInputAction.search,
       enabled = true;

  final TextEditingController? controller;
  final String? label;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final IconData? prefixIcon;
  final IconData? suffixIcon;
  final String? suffixText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool autofocus;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofocus: autofocus,
      enabled: enabled,
      style: t.typography.bodyMd.copyWith(color: t.colors.contentPrimary),
      cursorColor: t.colors.accentPrimary,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        filled: true,
        fillColor: t.colors.surfaceRaised,
        prefixIcon: prefixIcon == null
            ? null
            : Icon(prefixIcon, color: t.colors.contentTertiary, size: 18),
        suffixIcon: suffixIcon == null
            ? null
            : Icon(suffixIcon, color: t.colors.contentTertiary, size: 18),
        suffixText: suffixText,
        suffixStyle: t.typography.labelLg.copyWith(
          color: t.colors.contentSecondary,
        ),
        hintStyle: t.typography.bodyMd.copyWith(
          color: t.colors.contentTertiary,
        ),
        labelStyle: t.typography.bodySm.copyWith(
          color: t.colors.contentTertiary,
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: t.spacing.lg,
          vertical: t.spacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: t.radii.lgAll,
          borderSide: BorderSide(color: t.colors.borderDefault),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: t.radii.lgAll,
          borderSide: BorderSide(color: t.colors.borderDefault),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: t.radii.lgAll,
          borderSide: BorderSide(color: t.colors.accentPrimary, width: 1.4),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: t.radii.lgAll,
          borderSide: BorderSide(color: t.colors.borderSubtle),
        ),
      ),
    );
  }
}
