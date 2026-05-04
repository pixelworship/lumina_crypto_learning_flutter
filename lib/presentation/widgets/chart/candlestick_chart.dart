import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../design_system/lumina_ui.dart';
import '../../blocs/chart/chart_bloc.dart';
import '../../blocs/chart/chart_state.dart';
import 'chart_renderer.dart';

/// Top-level reusable candlestick chart.
///
/// Drop this anywhere a [ChartBloc] is provided in the widget tree —
/// it owns nothing local; everything (timeframe, candles, glow,
/// auto-scale, volume overlay, pause state, market events) flows from
/// the bloc's `ChartState`.
///
/// Loading UX:
///   * **Cache miss** — `candles` is empty: a centered loading
///     indicator fills the chart panel.
///   * **Cache hit, fresh data still in flight** — `candles` is
///     non-empty but `isLoadingHistory` is true: the cached chart
///     renders normally with a small loading badge in the top-right
///     so the user knows newer ticks are still loading.
///   * **Pagination in flight** — the user has scrolled to the left
///     edge and `isExtendingHistory` is true: the chart renders
///     normally with a small loading badge in the top-left while
///     older history is fetched from the historical API and
///     prepended.
///   * **Settled** — `candles` is non-empty and no loading flags are
///     set: full chart, no overlay.
class CandlestickChart extends StatelessWidget {
  const CandlestickChart({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChartBloc, ChartState>(
      buildWhen: (ChartState prev, ChartState next) =>
          prev.candles != next.candles ||
          prev.timeframe != next.timeframe ||
          prev.glowEnabled != next.glowEnabled ||
          prev.autoScaleEnabled != next.autoScaleEnabled ||
          prev.volumeOverlayEnabled != next.volumeOverlayEnabled ||
          prev.pauseStartedAt != next.pauseStartedAt ||
          prev.events != next.events ||
          prev.fills != next.fills ||
          prev.isLoadingHistory != next.isLoadingHistory ||
          prev.isExtendingHistory != next.isExtendingHistory,
      builder: (BuildContext context, ChartState state) {
        final LuminaTokens t = context.tokens;
        if (state.candles.isEmpty) {
          return Center(
            child: Padding(
              padding: EdgeInsets.all(t.spacing.xxl),
              child: const LuminaLoadingIndicator(),
            ),
          );
        }
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: ChartRenderer(
                candles: state.candles,
                timeframe: state.timeframe,
                glowEnabled: state.glowEnabled,
                autoScaleEnabled: state.autoScaleEnabled,
                volumeOverlayEnabled: state.volumeOverlayEnabled,
                pauseStartedAt: state.pauseStartedAt,
                events: state.events,
                fills: state.fills,
              ),
            ),
            if (state.isLoadingHistory)
              Positioned(
                top: t.spacing.sm,
                right: t.spacing.sm,
                child: const _ChartLoadingBadge(),
              ),
            if (state.isExtendingHistory)
              Positioned(
                top: t.spacing.sm,
                left: t.spacing.sm,
                child: const _ChartLoadingBadge(),
              ),
          ],
        );
      },
    );
  }
}

/// Compact "still loading" pill shown over the chart when fresh
/// history is in flight on top of a cached graph.
class _ChartLoadingBadge extends StatelessWidget {
  const _ChartLoadingBadge();

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return Material(
      color: t.colors.surfaceCanvas.withValues(alpha: 0.7),
      shape: const StadiumBorder(),
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: t.spacing.sm + 2,
          vertical: t.spacing.xs + 1,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: t.colors.accentPrimary,
              ),
            ),
            SizedBox(width: t.spacing.xs + 2),
            Text(
              'Loading',
              style: t.typography.labelSm.copyWith(
                color: t.colors.contentSecondary,
                letterSpacing: 0.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
