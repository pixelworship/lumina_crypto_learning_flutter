import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../design_system/lumina_ui.dart';
import '../../blocs/chart/chart_bloc.dart';
import '../../blocs/chart/chart_state.dart';

/// Bold red banner shown while the live tick stream is paused. Anchored
/// at the top of the chart so it doesn't compete with the candles for
/// the eye.
class NoLiveDataIndicator extends StatelessWidget {
  const NoLiveDataIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocSelector<ChartBloc, ChartState, bool>(
      selector: (ChartState state) => state.isPaused,
      builder: (BuildContext context, bool paused) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (Widget child, Animation<double> animation) =>
              FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.3),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: paused ? const _Box() : const SizedBox.shrink(),
        );
      },
    );
  }
}

class _Box extends StatelessWidget {
  const _Box();

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return Material(
      color: t.colors.feedbackNegative,
      shape: const CircleBorder(),
      elevation: 8,
      child: Container(
        padding: EdgeInsets.all(t.spacing.sm + 2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: t.colors.feedbackNegative.withValues(alpha: 0.7),
            width: 1.5,
          ),
        ),
        child: const Icon(
          Icons.error_outline,
          color: Colors.white,
          size: 24,
        ),
      ),
    );
  }
}
