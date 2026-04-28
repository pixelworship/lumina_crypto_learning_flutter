import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Cubit that owns the current [ThemeMode].
///
/// Wiring this to [MaterialApp.themeMode] is all it takes to hot-swap themes
/// — every widget reads tokens through the design system, so the change
/// propagates automatically.
class ThemeModeCubit extends Cubit<ThemeMode> {
  ThemeModeCubit({ThemeMode initial = ThemeMode.dark}) : super(initial);

  void setMode(ThemeMode mode) => emit(mode);

  void toggle() {
    emit(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  }
}
