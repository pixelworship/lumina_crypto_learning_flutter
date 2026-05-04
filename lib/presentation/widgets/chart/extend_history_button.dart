import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../design_system/lumina_ui.dart';
import '../../blocs/chart/chart_bloc.dart';
import '../../blocs/chart/chart_event.dart';
import '../../blocs/chart/chart_state.dart';

/// FAB that asks the bloc to fetch another window of older history equal
/// in span to whatever is already loaded. Each press effectively doubles
/// the available backlog (1y → 2y → 4y → ...) until the in-memory tick
/// cap starts trimming the oldest entries off the front.
class ExtendHistoryButton extends StatelessWidget {
  const ExtendHistoryButton({super.key});

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return BlocSelector<ChartBloc, ChartState, _ExtendHistoryVm>(
      selector: (ChartState state) => _ExtendHistoryVm(
        hasHistory: state.candles.isNotEmpty,
        isExtending: state.isExtendingHistory,
      ),
      builder: (BuildContext context, _ExtendHistoryVm vm) {
        final bool disabled = !vm.hasHistory || vm.isExtending;
        return FloatingActionButton.small(
          heroTag: 'extend-history',
          tooltip: vm.isExtending
              ? 'Loading older history…'
              : (vm.hasHistory
                  ? 'Double historic range'
                  : 'Waiting for initial history'),
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
                  .add(const HistoryExtendRequested()),
          child: vm.isExtending
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: t.colors.contentSecondary,
                  ),
                )
              : const Icon(Icons.history),
        );
      },
    );
  }
}

class _ExtendHistoryVm {
  const _ExtendHistoryVm({
    required this.hasHistory,
    required this.isExtending,
  });

  final bool hasHistory;
  final bool isExtending;

  @override
  bool operator ==(Object other) =>
      other is _ExtendHistoryVm &&
      other.hasHistory == hasHistory &&
      other.isExtending == isExtending;

  @override
  int get hashCode => Object.hash(hasHistory, isExtending);
}
