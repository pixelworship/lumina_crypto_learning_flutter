import 'package:flutter/material.dart';

import '../../tokens/lumina_tokens.dart';

/// Compact horizontal segmented control. Generic over option type.
///
/// Suitable for short option lists where every option fits on screen
/// (e.g. a chart range selector). For long lists, prefer [LuminaChipBar].
class LuminaSegmentedControl<T> extends StatelessWidget {
  const LuminaSegmentedControl({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    required this.labelOf,
    this.scrollable = true,
  });

  final List<T> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final String Function(T) labelOf;

  /// When `true` (the default), wraps the row in a horizontal [ListView] so
  /// it can overflow gracefully. Set to `false` for a fixed equally-spaced
  /// segmented control.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;

    Widget segment(T option) {
      final bool isSelected = option == selected;
      return GestureDetector(
        onTap: () => onChanged(option),
        child: AnimatedContainer(
          duration: t.motion.fast,
          curve: t.motion.standardEase,
          padding: EdgeInsets.symmetric(
            horizontal: t.spacing.md + 2,
            vertical: t.spacing.xs + 2,
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? t.colors.accentPrimary
                : t.colors.surfaceRaised,
            borderRadius: t.radii.smAll,
            border: Border.all(
              color: isSelected
                  ? t.colors.accentPrimary
                  : t.colors.borderDefault,
            ),
          ),
          child: Center(
            child: Text(
              labelOf(option),
              style: t.typography.labelMd.copyWith(
                color: isSelected
                    ? t.colors.onAccentPrimary
                    : t.colors.contentSecondary,
              ),
            ),
          ),
        ),
      );
    }

    if (!scrollable) {
      return Row(
        children: <Widget>[
          for (int i = 0; i < options.length; i++) ...<Widget>[
            if (i > 0) SizedBox(width: t.spacing.xs + 2),
            Expanded(child: segment(options[i])),
          ],
        ],
      );
    }

    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (BuildContext context, int index) =>
            SizedBox(width: t.spacing.xs + 2),
        itemBuilder: (BuildContext context, int index) =>
            segment(options[index]),
      ),
    );
  }
}
