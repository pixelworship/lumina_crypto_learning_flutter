import 'package:flutter/material.dart';

import '../../tokens/lumina_tokens.dart';

/// Pill-shaped, single-select chip used in filter rows.
class LuminaChip extends StatelessWidget {
  const LuminaChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.leadingIcon,
  });

  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final IconData? leadingIcon;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;

    final Color background =
        selected ? t.colors.accentPrimary : t.colors.surfaceRaised;
    final Color foreground = selected
        ? t.colors.onAccentPrimary
        : t.colors.contentSecondary;
    final Color borderColor = selected
        ? t.colors.accentPrimary
        : t.colors.borderDefault;

    return Material(
      color: background,
      borderRadius: t.radii.pillAll,
      child: InkWell(
        onTap: () => onSelected(!selected),
        borderRadius: t.radii.pillAll,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: t.spacing.md + 2,
            vertical: t.spacing.xs + 2,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: borderColor),
            borderRadius: t.radii.pillAll,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (leadingIcon != null) ...<Widget>[
                Icon(leadingIcon, size: 14, color: foreground),
                SizedBox(width: t.spacing.xs),
              ],
              Text(
                label,
                style: t.typography.labelLg.copyWith(color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal scrolling row of [LuminaChip]s. Generic over the option type so
/// it can be used for categories, time ranges, anything pickable.
class LuminaChipBar<T> extends StatelessWidget {
  const LuminaChipBar({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    required this.labelOf,
    this.iconOf,
  });

  final List<T> options;
  final T selected;
  final ValueChanged<T> onSelected;
  final String Function(T) labelOf;
  final IconData? Function(T)? iconOf;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: options.length,
        separatorBuilder: (BuildContext context, int index) =>
            SizedBox(width: t.spacing.sm),
        itemBuilder: (BuildContext context, int index) {
          final T option = options[index];
          return LuminaChip(
            label: labelOf(option),
            selected: option == selected,
            onSelected: (_) => onSelected(option),
            leadingIcon: iconOf?.call(option),
          );
        },
      ),
    );
  }
}
