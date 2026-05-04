import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/utils/formatters.dart';
import '../../../design_system/lumina_ui.dart';
import '../../blocs/chart/chart_bloc.dart';
import '../../blocs/chart/chart_event.dart';
import '../../blocs/chart/chart_state.dart';

/// Floating action buttons that bump the live mock price down/up by a
/// fixed step. Useful for exercising flash-crash / spike rendering paths.
class DebugPriceOffsetControls extends StatelessWidget {
  const DebugPriceOffsetControls({super.key, this.step = 25.0});

  final double step;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return BlocSelector<ChartBloc, ChartState, double>(
      selector: (ChartState state) => state.priceOffset,
      builder: (BuildContext context, double offset) {
        final ChartBloc bloc = context.read<ChartBloc>();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            FloatingActionButton.small(
              heroTag: 'price-offset-down',
              tooltip: 'Drop price',
              onPressed: () =>
                  bloc.add(PriceOffsetChanged(offset - step)),
              child: const Icon(Icons.trending_down),
            ),
            SizedBox(width: t.spacing.sm),
            _OffsetReadout(offset: offset),
            SizedBox(width: t.spacing.sm),
            FloatingActionButton.small(
              heroTag: 'price-offset-up',
              tooltip: 'Spike price',
              onPressed: () =>
                  bloc.add(PriceOffsetChanged(offset + step)),
              child: const Icon(Icons.trending_up),
            ),
          ],
        );
      },
    );
  }
}

class _OffsetReadout extends StatelessWidget {
  const _OffsetReadout({required this.offset});

  final double offset;

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
        child: LuminaDelta(
          isPositive: offset > 0,
          isZero: offset == 0,
          text: Formatters.currency(offset.abs()),
          style: t.typography.labelLg,
        ),
      ),
    );
  }
}
