import 'package:flutter_bloc/flutter_bloc.dart';

/// Tabs in the bottom navigation bar.
///
/// The order here drives the order of tabs and screens, so be deliberate about
/// reordering this enum. There used to be a `trade` tab here; it was removed
/// in favor of pushing the asset detail screen as a route from the markets /
/// watchlist rows directly.
enum AppTab { home, markets, portfolio, profile }

/// Lightweight cubit owning the currently selected tab.
class NavigationCubit extends Cubit<AppTab> {
  NavigationCubit() : super(AppTab.markets);

  void select(AppTab tab) => emit(tab);
}
