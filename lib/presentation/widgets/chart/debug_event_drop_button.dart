import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../design_system/lumina_ui.dart';
import '../../blocs/chart/chart_bloc.dart';
import '../../blocs/chart/chart_event.dart';

/// FAB that drops a randomly-picked mock market event onto the chart at
/// the current moment. The bloc also auto-spawns events on a timer; this
/// is a manual on-demand trigger for demos.
class DebugEventDropButton extends StatelessWidget {
  const DebugEventDropButton({super.key});

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return FloatingActionButton.small(
      heroTag: 'event-drop',
      tooltip: 'Drop random event on chart',
      backgroundColor: t.colors.accentSecondary,
      foregroundColor: t.colors.contentInverse,
      onPressed: () => context
          .read<ChartBloc>()
          .add(const MarketEventSpawnRequested()),
      child: const Icon(Icons.bolt),
    );
  }
}
