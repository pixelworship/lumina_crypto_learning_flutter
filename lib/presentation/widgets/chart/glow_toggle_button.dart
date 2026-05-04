import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../design_system/lumina_ui.dart';
import '../../blocs/chart/chart_bloc.dart';
import '../../blocs/chart/chart_event.dart';
import '../../blocs/chart/chart_state.dart';

/// Toolbar action that toggles candle glow + ambient lava-lamp backdrop.
class GlowToggleButton extends StatelessWidget {
  const GlowToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocSelector<ChartBloc, ChartState, bool>(
      selector: (ChartState state) => state.glowEnabled,
      builder: (BuildContext context, bool enabled) {
        return LuminaIconButton(
          tooltip: enabled ? 'Disable glow' : 'Enable glow',
          icon: enabled ? Icons.auto_awesome : Icons.auto_awesome_outlined,
          variant: enabled
              ? LuminaIconButtonVariant.accent
              : LuminaIconButtonVariant.surface,
          onPressed: () =>
              context.read<ChartBloc>().add(const GlowToggled()),
        );
      },
    );
  }
}
