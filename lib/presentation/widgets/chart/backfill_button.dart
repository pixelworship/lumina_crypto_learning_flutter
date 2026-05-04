import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../design_system/lumina_ui.dart';
import '../../blocs/chart/chart_bloc.dart';
import '../../blocs/chart/chart_event.dart';
import '../../blocs/chart/chart_state.dart';

/// FAB that asks the bloc to fetch mock ticks for every resolved pause
/// gap and merge them back into history, replacing "DATA UNAVAILABLE"
/// slots with real candles. Disabled when there's nothing to fill.
class BackfillButton extends StatelessWidget {
  const BackfillButton({super.key});

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return BlocSelector<ChartBloc, ChartState, _BackfillVm>(
      selector: (ChartState state) => _BackfillVm(
        hasGaps: state.candles.any((c) => c.isGap),
        isBackfilling: state.isBackfilling,
      ),
      builder: (BuildContext context, _BackfillVm vm) {
        final bool disabled = !vm.hasGaps || vm.isBackfilling;
        return FloatingActionButton.small(
          heroTag: 'backfill-gaps',
          tooltip: vm.isBackfilling
              ? 'Backfilling…'
              : (vm.hasGaps
                  ? 'Backfill missing data'
                  : 'No gaps to backfill'),
          backgroundColor: disabled
              ? t.colors.surfaceMuted
              : t.colors.surfaceRaised,
          foregroundColor: disabled
              ? t.colors.contentTertiary
              : t.colors.contentPrimary,
          onPressed: disabled
              ? null
              : () => context
                  .read<ChartBloc>()
                  .add(const BackfillRequested()),
          child: vm.isBackfilling
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: t.colors.contentSecondary,
                  ),
                )
              : const Icon(Icons.cloud_download_outlined),
        );
      },
    );
  }
}

class _BackfillVm {
  const _BackfillVm({required this.hasGaps, required this.isBackfilling});

  final bool hasGaps;
  final bool isBackfilling;

  @override
  bool operator ==(Object other) =>
      other is _BackfillVm &&
      other.hasGaps == hasGaps &&
      other.isBackfilling == isBackfilling;

  @override
  int get hashCode => Object.hash(hasGaps, isBackfilling);
}
