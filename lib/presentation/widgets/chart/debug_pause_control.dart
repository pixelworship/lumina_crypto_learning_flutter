import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../design_system/lumina_ui.dart';
import '../../blocs/chart/chart_bloc.dart';
import '../../blocs/chart/chart_event.dart';
import '../../blocs/chart/chart_state.dart';

/// FAB that pauses / resumes the live tick stream. While paused,
/// broadcast events are dropped (not buffered), simulating a network
/// outage.
class DebugPauseControl extends StatelessWidget {
  const DebugPauseControl({super.key});

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return BlocSelector<ChartBloc, ChartState, bool>(
      selector: (ChartState state) => state.isPaused,
      builder: (BuildContext context, bool paused) {
        return FloatingActionButton.small(
          heroTag: 'stream-pause-toggle',
          tooltip:
              paused ? 'Resume stream' : 'Pause stream (simulate offline)',
          backgroundColor: paused
              ? t.colors.feedbackWarning
              : t.colors.surfaceRaised,
          foregroundColor: paused
              ? t.colors.contentInverse
              : t.colors.contentPrimary,
          onPressed: () =>
              context.read<ChartBloc>().add(const PauseToggled()),
          child: Icon(paused ? Icons.play_arrow : Icons.pause),
        );
      },
    );
  }
}
