import 'package:flutter_bloc/flutter_bloc.dart';

/// App-wide toggle for the dashed "open" reference line drawn on
/// every sparkline (`PriceSparkline` on the balance card,
/// `AssetSparkline` on markets and watchlist rows).
///
/// Defaults to false — the dashed line is intentionally hidden in the
/// shipping UI because in casual scanning it competes with the live
/// stroke for the eye's attention. The debug FAB on `MainShell` flips
/// this on so the line can be re-enabled while inspecting price
/// movement against the period's open.
///
/// Lives at the app level (not scoped to a screen) because both home
/// and markets render sparklines simultaneously — a screen-scoped
/// cubit would force the toggle to be re-set every navigation.
class SparklineOpenLineCubit extends Cubit<bool> {
  SparklineOpenLineCubit() : super(false);

  void toggle() => emit(!state);
}
