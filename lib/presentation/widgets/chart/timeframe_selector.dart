import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../data/models/timeframe.dart';
import '../../../design_system/lumina_ui.dart';
import '../../blocs/chart/chart_bloc.dart';
import '../../blocs/chart/chart_event.dart';
import '../../blocs/chart/chart_state.dart';

/// Horizontal pill row of candle timeframes (1s ... 1h).
///
/// Built on top of [LuminaSegmentedControl] so the chart timeframe
/// selector shares the look + behavior of every other segmented control
/// in the app.
class TimeframeSelector extends StatelessWidget {
  const TimeframeSelector({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocSelector<ChartBloc, ChartState, Timeframe>(
      selector: (ChartState state) => state.timeframe,
      builder: (BuildContext context, Timeframe timeframe) {
        return LuminaSegmentedControl<Timeframe>(
          options: Timeframe.values,
          selected: timeframe,
          labelOf: (Timeframe tf) => tf.label,
          onChanged: (Timeframe tf) =>
              context.read<ChartBloc>().add(TimeframeChanged(tf)),
        );
      },
    );
  }
}
