import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../design_system/lumina_ui.dart';
import '../../blocs/chart/chart_bloc.dart';
import '../../blocs/chart/chart_event.dart';
import '../../blocs/chart/chart_state.dart';

/// Toolbar action that toggles automatic vertical price-range scaling.
///
/// When enabled (the default), the chart re-fits its vertical range to
/// the currently-visible candles each frame so newly arriving high/low
/// ticks always remain on screen. When disabled, the range is frozen at
/// whatever it was at the moment of toggle and ticks outside that band
/// are clipped.
class AutoScaleToggleButton extends StatelessWidget {
  const AutoScaleToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocSelector<ChartBloc, ChartState, bool>(
      selector: (ChartState state) => state.autoScaleEnabled,
      builder: (BuildContext context, bool enabled) {
        return LuminaIconButton(
          tooltip: enabled ? 'Disable auto-scale' : 'Enable auto-scale',
          icon: enabled ? Icons.unfold_more : Icons.unfold_less,
          variant: enabled
              ? LuminaIconButtonVariant.accent
              : LuminaIconButtonVariant.surface,
          onPressed: () =>
              context.read<ChartBloc>().add(const AutoScaleToggled()),
        );
      },
    );
  }
}
