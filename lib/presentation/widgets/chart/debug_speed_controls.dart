import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../design_system/lumina_ui.dart';
import '../../blocs/chart/chart_bloc.dart';
import '../../blocs/chart/chart_event.dart';
import '../../blocs/chart/chart_state.dart';

/// Floating action buttons that double / halve the mock tick emission
/// rate.
class DebugSpeedControls extends StatelessWidget {
  const DebugSpeedControls({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocSelector<ChartBloc, ChartState, double>(
      selector: (ChartState state) => state.tickSpeed,
      builder: (BuildContext context, double speed) {
        final ChartBloc bloc = context.read<ChartBloc>();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            FloatingActionButton.small(
              heroTag: 'tick-speed-down',
              tooltip: 'Slow down ticks',
              onPressed: () => bloc.add(TickSpeedChanged(speed / 2)),
              child: const Icon(Icons.remove),
            ),
            const SizedBox(width: 8),
            _SpeedReadout(speed: speed),
            const SizedBox(width: 8),
            FloatingActionButton.small(
              heroTag: 'tick-speed-up',
              tooltip: 'Speed up ticks',
              onPressed: () => bloc.add(TickSpeedChanged(speed * 2)),
              child: const Icon(Icons.add),
            ),
          ],
        );
      },
    );
  }
}

class _SpeedReadout extends StatelessWidget {
  const _SpeedReadout({required this.speed});

  final double speed;

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
          '${_format(speed)}x',
          style: t.typography.labelLg.copyWith(
            color: t.colors.contentPrimary,
          ),
        ),
      ),
    );
  }

  String _format(double v) {
    if (v >= 1) return v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 1);
    return v
        .toStringAsFixed(3)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
}
