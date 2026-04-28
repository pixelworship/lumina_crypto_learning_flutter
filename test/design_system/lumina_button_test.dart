import 'package:flutter/material.dart';
import 'package:flutter_demo/design_system/lumina_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

Widget _wrap(Widget child) =>
    MaterialApp(theme: LuminaTheme.dark(), home: Scaffold(body: child));

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('LuminaButton', () {
    testWidgets('renders the label text', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrap(LuminaButton.primary(label: 'Continue', onPressed: () {})),
      );
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('triggers onPressed when tapped', (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(
        _wrap(
          LuminaButton.primary(label: 'Tap me', onPressed: () => taps += 1),
        ),
      );
      await tester.tap(find.byType(LuminaButton));
      expect(taps, 1);
    });

    testWidgets('does not call onPressed when disabled', (
      WidgetTester tester,
    ) async {
      int taps = 0;
      await tester.pumpWidget(
        _wrap(
          LuminaButton.primary(
            label: 'Disabled',
            onPressed: null,
          ),
        ),
      );
      await tester.tap(find.byType(LuminaButton));
      expect(taps, 0);
    });

    testWidgets('shows a progress indicator while loading', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          LuminaButton.primary(
            label: 'Submit',
            onPressed: () {},
            isLoading: true,
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('isLoading takes precedence and suppresses the tap', (
      WidgetTester tester,
    ) async {
      int taps = 0;
      await tester.pumpWidget(
        _wrap(
          LuminaButton.primary(
            label: 'Submit',
            onPressed: () => taps += 1,
            isLoading: true,
          ),
        ),
      );
      await tester.tap(find.byType(LuminaButton));
      expect(taps, 0);
    });

    testWidgets('renders leading + trailing icons when not loading', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          LuminaButton.primary(
            label: 'Continue',
            onPressed: () {},
            leadingIcon: Icons.lock_outline,
            trailingIcon: Icons.arrow_forward_rounded,
          ),
        ),
      );
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.byIcon(Icons.arrow_forward_rounded), findsOneWidget);
    });

    testWidgets('supports every variant', (WidgetTester tester) async {
      for (final LuminaButtonVariant variant in LuminaButtonVariant.values) {
        await tester.pumpWidget(
          _wrap(
            LuminaButton(
              label: variant.name,
              variant: variant,
              onPressed: () {},
            ),
          ),
        );
        expect(find.text(variant.name), findsOneWidget);
      }
    });

    testWidgets('expand=true makes the row stretch to its parent', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            width: 320,
            child: LuminaButton.primary(
              label: 'Wide',
              onPressed: () {},
              expand: true,
            ),
          ),
        ),
      );
      final Size buttonSize = tester.getSize(find.byType(LuminaButton));
      expect(buttonSize.width, 320);
    });
  });
}
