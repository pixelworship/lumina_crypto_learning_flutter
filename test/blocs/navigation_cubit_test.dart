import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_demo/presentation/blocs/navigation/navigation_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NavigationCubit', () {
    blocTest<NavigationCubit, AppTab>(
      'starts on the markets tab',
      build: NavigationCubit.new,
      verify: (NavigationCubit cubit) => expect(cubit.state, AppTab.markets),
    );

    blocTest<NavigationCubit, AppTab>(
      'select() changes the active tab',
      build: NavigationCubit.new,
      act: (NavigationCubit cubit) => cubit.select(AppTab.portfolio),
      expect: () => <AppTab>[AppTab.portfolio],
    );
  });
}
