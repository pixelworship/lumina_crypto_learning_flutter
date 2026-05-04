import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../design_system/lumina_ui.dart';
import '../../blocs/chart/chart_bloc.dart';
import '../../blocs/chart/chart_event.dart';
import '../../blocs/chart/chart_state.dart';

/// Debug FAB that toggles the translucent volume area chart drawn
/// behind the candles. Off by default.
class VolumeOverlayToggleButton extends StatelessWidget {
  const VolumeOverlayToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return BlocSelector<ChartBloc, ChartState, bool>(
      selector: (ChartState state) => state.volumeOverlayEnabled,
      builder: (BuildContext context, bool enabled) {
        return FloatingActionButton.small(
          heroTag: 'volume-overlay-toggle',
          tooltip:
              enabled ? 'Hide volume overlay' : 'Show volume overlay',
          backgroundColor:
              enabled ? t.colors.chartVolumeArea : t.colors.surfaceRaised,
          foregroundColor:
              enabled ? t.colors.contentInverse : t.colors.contentPrimary,
          onPressed: () =>
              context.read<ChartBloc>().add(const VolumeOverlayToggled()),
          child: Icon(enabled ? Icons.bar_chart : Icons.bar_chart_outlined),
        );
      },
    );
  }
}
