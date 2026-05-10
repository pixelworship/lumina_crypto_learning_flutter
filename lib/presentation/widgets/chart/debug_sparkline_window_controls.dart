import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/services/sparkline_feed.dart';
import '../../../design_system/lumina_ui.dart';

/// Floating action buttons that step the trailing-window duration of
/// every row sparkline (markets + watchlist) up and down through a
/// fixed preset list. Each press triggers a re-seed from the
/// warehouse against the new range, so rows shimmer briefly and
/// then come back with the updated shape.
///
/// Lives on the chart's debug speed-dial even though sparklines
/// render on the markets/watchlist tabs — the user navigates back
/// out of the asset detail screen to verify, which is acceptable for
/// a debug-only knob.
class DebugSparklineWindowControls extends StatelessWidget {
  const DebugSparklineWindowControls({super.key});

  /// Steps the user can dial through. Geometric-ish progression so a
  /// couple of presses moves between meaningfully different ranges
  /// (matching the chart's own range selector defaults).
  static const List<Duration> presets = <Duration>[
    Duration(hours: 1),
    Duration(hours: 6),
    Duration(hours: 24),
    Duration(days: 3),
    Duration(days: 7),
    Duration(days: 30),
  ];

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    final SparklineFeed feed = context.read<SparklineFeed>();
    return ValueListenableBuilder<Duration>(
      valueListenable: feed.historyWindowListenable,
      builder: (BuildContext context, Duration window, Widget? _) {
        final int idx = _nearestPresetIndex(window);
        final bool atMin = idx <= 0;
        final bool atMax = idx >= presets.length - 1;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            FloatingActionButton.small(
              heroTag: 'sparkline-window-down',
              tooltip: 'Shorten sparkline window',
              onPressed: atMin
                  ? null
                  : () => feed.setHistoryWindow(presets[idx - 1]),
              backgroundColor:
                  atMin ? t.colors.surfaceMuted : null,
              foregroundColor:
                  atMin ? t.colors.contentTertiary : null,
              child: const Icon(Icons.unfold_less),
            ),
            SizedBox(width: t.spacing.sm),
            _WindowReadout(window: window),
            SizedBox(width: t.spacing.sm),
            FloatingActionButton.small(
              heroTag: 'sparkline-window-up',
              tooltip: 'Lengthen sparkline window',
              onPressed: atMax
                  ? null
                  : () => feed.setHistoryWindow(presets[idx + 1]),
              backgroundColor:
                  atMax ? t.colors.surfaceMuted : null,
              foregroundColor:
                  atMax ? t.colors.contentTertiary : null,
              child: const Icon(Icons.unfold_more),
            ),
          ],
        );
      },
    );
  }

  /// Index of the preset closest (in ms) to [window]. The current
  /// value isn't guaranteed to be in [presets] — e.g. tests or
  /// production wiring might pass a custom default — so we snap to
  /// the nearest preset rather than refusing to render.
  static int _nearestPresetIndex(Duration window) {
    int best = 0;
    int bestDiff = (presets[0].inMilliseconds - window.inMilliseconds).abs();
    for (int i = 1; i < presets.length; i++) {
      final int diff =
          (presets[i].inMilliseconds - window.inMilliseconds).abs();
      if (diff < bestDiff) {
        best = i;
        bestDiff = diff;
      }
    }
    return best;
  }
}

class _WindowReadout extends StatelessWidget {
  const _WindowReadout({required this.window});

  final Duration window;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return Material(
      color: t.colors.surfaceRaised,
      borderRadius: t.radii.pillAll,
      elevation: 4,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: t.spacing.md,
          vertical: t.spacing.sm,
        ),
        child: Text(
          _format(window),
          style: t.typography.numericSm.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
            color: t.colors.contentPrimary,
          ),
        ),
      ),
    );
  }

  String _format(Duration d) {
    if (d.inDays >= 1) return '${d.inDays}d';
    if (d.inHours >= 1) return '${d.inHours}h';
    if (d.inMinutes >= 1) return '${d.inMinutes}m';
    return '${d.inSeconds}s';
  }
}
