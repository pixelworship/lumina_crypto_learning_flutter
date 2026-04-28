import 'package:flutter_bloc/flutter_bloc.dart';

/// Tabs in the bottom navigation bar.
///
/// The order here drives the order of tabs and screens, so be deliberate about
/// reordering this enum.
enum AppTab { home, markets, trade, portfolio, profile }

/// Lightweight cubit owning the currently selected tab.
class NavigationCubit extends Cubit<AppTab> {
  NavigationCubit() : super(AppTab.markets);

  void select(AppTab tab) => emit(tab);
}
