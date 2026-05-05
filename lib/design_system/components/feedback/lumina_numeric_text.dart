import 'package:flutter/material.dart';

/// A [Text] that reserves layout width for a fixed reservation
/// [template] instead of for its own current value.
///
/// Use anywhere a numeric label changes between values whose
/// rendered widths differ — e.g. a row's price text that flips
/// between `$9.99`, `$11.37`, `$156.99`, `$3.9K`, `$62.9K` as
/// live ticks arrive. The mono numeric scale paints in JetBrains
/// Mono with `FontFeature.tabularFigures()`, so every digit
/// advance is stable; the width difference between values comes
/// entirely from string length. Pinning the text's layout to the
/// longest string the source formatter can produce is what keeps
/// adjacent widgets — sparkline minimaps, change pills, the row
/// boundary itself — from shimmying when the value ticks across
/// a digit-count boundary.
///
/// Layout shape: a [Stack] with two non-positioned children.
///   1. An invisible (but layout-sized) [Text] painting [template]
///      under [style] — establishes the stack's natural width.
///   2. The visible [Text] painting [text] aligned to [textAlign].
///
/// The stack sizes itself to the wider child. Because [template]
/// is by contract at least as wide as any [text] the caller will
/// pass, the stack's width is the template's width — stable
/// across every value tick.
///
/// No [TextPainter], no per-style width cache, no hardcoded pixel
/// reservation. Flutter's layout engine measures the template the
/// same way it measures the visible text, so this widget is
/// automatically correct for any typography change (theme switch,
/// platform font fallback, accessibility scaling).
///
/// ### When NOT to use this
///
/// Don't use this for non-monospace text. With proportional fonts
/// the same string is the same width either way, but two
/// different strings of equal character count will lay out
/// differently — the template approach can't compensate for
/// per-glyph advance variation. For mono numerics it's exact.
class LuminaNumericText extends StatelessWidget {
  const LuminaNumericText({
    super.key,
    required this.text,
    required this.template,
    required this.style,
    this.textAlign = TextAlign.end,
  });

  /// The visible value, e.g. `$11.37`, `2.40%`, `64,250`.
  final String text;

  /// The widest string the source formatter can produce in this
  /// context, e.g. `$999.9T` for compact USD, `9999.99%` for an
  /// uncapped change pct, `999,999.999999` for a full-precision
  /// crypto quantity. With tabular figures the only width signal
  /// is character count, so [template] just needs to be at least
  /// as long as the longest [text] this widget will ever receive.
  final String template;

  /// Required so both the template and the visible text lay out
  /// under the same metrics — passing different styles to each
  /// would defeat the whole point.
  final TextStyle style;

  /// Where the visible value sits inside the reserved footprint.
  /// Defaults to [TextAlign.end] because the dominant use case is
  /// a right-aligned trailing column of a list row.
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final Alignment alignment = switch (textAlign) {
      TextAlign.start || TextAlign.left => Alignment.centerLeft,
      TextAlign.center || TextAlign.justify => Alignment.center,
      TextAlign.end || TextAlign.right => Alignment.centerRight,
    };
    return Stack(
      alignment: alignment,
      children: <Widget>[
        // Invisible width-pinning template. `maintainSize: true`
        // keeps it in the layout (consuming its full natural
        // width) while suppressing the paint pass — so the stack
        // sizes itself to the template's footprint, but the
        // pixels visible on screen are exclusively the live
        // value.
        Visibility(
          visible: false,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: Text(
            template,
            style: style,
            maxLines: 1,
            softWrap: false,
          ),
        ),
        Text(
          text,
          style: style,
          maxLines: 1,
          softWrap: false,
          textAlign: textAlign,
        ),
      ],
    );
  }
}
