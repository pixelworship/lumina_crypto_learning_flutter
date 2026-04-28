import 'package:flutter/material.dart';
import 'package:flutter_demo/app.dart';
import 'package:flutter_demo/data/services/mock_api_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Lumina Crypto smoke tests', () {
    testWidgets('app boots, loads markets and shows the asset list', (
      WidgetTester tester,
    ) async {
      // Use a zero-latency mock API so the test settles quickly.
      await tester.pumpWidget(
        LuminaApp(
          apiOverride: MockApiService(latency: Duration.zero, seed: 1),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lumina Crypto'), findsOneWidget);
      expect(find.text('Market Discovery'), findsOneWidget);
      expect(find.text('Bitcoin'), findsWidgets);
      expect(find.text('Ethereum'), findsWidgets);
    });

    testWidgets('switching to Home tab shows Total Balance', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        LuminaApp(
          apiOverride: MockApiService(latency: Duration.zero, seed: 1),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('HOME'));
      await tester.pumpAndSettle();

      expect(find.text('TOTAL BALANCE'), findsOneWidget);
      expect(find.text('Watchlist'), findsOneWidget);
      expect(find.text('DEPOSIT'), findsOneWidget);
      expect(find.text('WITHDRAW'), findsOneWidget);
      expect(find.text('SWAP'), findsOneWidget);
    });

    testWidgets('switching to Portfolio tab shows allocation + holdings', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        LuminaApp(
          apiOverride: MockApiService(latency: Duration.zero, seed: 1),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('PORTFOLIO'));
      await tester.pumpAndSettle();

      expect(find.text('TOTAL PORTFOLIO VALUE'), findsOneWidget);
      expect(find.text('Allocation'), findsOneWidget);
      expect(find.text('My Assets'), findsOneWidget);
    });

    testWidgets('switching to Trade tab shows pair header + range selector', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        LuminaApp(
          apiOverride: MockApiService(latency: Duration.zero, seed: 1),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('TRADE'));
      await tester.pumpAndSettle();

      expect(find.text('BTC / USDT'), findsOneWidget);
      expect(find.text('1H'), findsOneWidget);
      expect(find.text('1D'), findsOneWidget);
      expect(find.text('BIDS'), findsOneWidget);
      expect(find.text('ASKS'), findsOneWidget);
    });

    testWidgets('search filters the markets list', (WidgetTester tester) async {
      await tester.pumpWidget(
        LuminaApp(
          apiOverride: MockApiService(latency: Duration.zero, seed: 1),
        ),
      );
      await tester.pumpAndSettle();

      // Find text field by hint.
      final Finder field = find.widgetWithText(
        TextField,
        'Search tokens, pairs, or categories...',
      );
      expect(field, findsOneWidget);

      await tester.enterText(field, 'sol');
      await tester.pumpAndSettle();

      expect(find.text('Solana'), findsOneWidget);
      expect(find.text('Bitcoin'), findsNothing);
    });
  });
}
