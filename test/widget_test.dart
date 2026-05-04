import 'package:flutter/material.dart';
import 'package:flutter_demo/app.dart';
import 'package:flutter_demo/data/services/asset_catalog.dart';
import 'package:flutter_demo/data/services/live_price_feed.dart';
import 'package:flutter_demo/data/services/mock_api_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps a few discrete frames to give the BLoCs time to load mock data
/// and rebuild. We can't use `pumpAndSettle` because the asset detail
/// screen renders the ambient lava-lamp `PriceFlashOverlay` which drives
/// a continuous Ticker — there's no idle frame to settle to.
Future<void> _pumpMicroTask(WidgetTester tester) async {
  for (int i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Builds a `LuminaApp` with the chart's live tick stream paused and
/// a paused [LivePriceFeed] inside the override `MockApiService`, so
/// the test doesn't have to chase pending timers in `pumpAndSettle`.
Widget _buildApp() {
  return LuminaApp(
    apiOverride: MockApiService(
      latency: Duration.zero,
      seed: 1,
      priceFeed: LivePriceFeed(
        catalog: StaticAssetCatalog(),
        startPaused: true,
      ),
    ),
    startChartStreaming: false,
  );
}

void main() {
  group('Lumina Crypto smoke tests', () {
    testWidgets('app boots, loads markets and shows the asset list', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await _pumpMicroTask(tester);

      expect(find.text('Lumina Crypto'), findsOneWidget);
      expect(find.text('Market Discovery'), findsOneWidget);
      expect(find.text('Bitcoin'), findsWidgets);
      expect(find.text('Ethereum'), findsWidgets);
    });

    testWidgets('switching to Home tab shows Total Balance', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await _pumpMicroTask(tester);

      await tester.tap(find.text('HOME'));
      await _pumpMicroTask(tester);

      expect(find.text('TOTAL BALANCE'), findsOneWidget);
      expect(find.text('Watchlist'), findsOneWidget);
      expect(find.text('DEPOSIT'), findsOneWidget);
      expect(find.text('WITHDRAW'), findsOneWidget);
      expect(find.text('BUY'), findsOneWidget);
    });

    testWidgets('switching to Portfolio tab shows allocation + holdings', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await _pumpMicroTask(tester);

      await tester.tap(find.text('PORTFOLIO'));
      await _pumpMicroTask(tester);

      expect(find.text('TOTAL PORTFOLIO VALUE'), findsOneWidget);
      expect(find.text('Allocation'), findsOneWidget);
      expect(find.text('My Assets'), findsOneWidget);
    });

    testWidgets(
        'tapping an asset in markets pushes a fresh asset detail page', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(_buildApp());
      await _pumpMicroTask(tester);

      // The dedicated Trade tab is gone — the detail screen is now
      // pushed as a route from the markets list. Tapping Bitcoin
      // should open a fresh detail page seeded with `BTC`.
      await tester.tap(find.text('Bitcoin').first);
      await _pumpMicroTask(tester);

      // Pair header (visible on the detail page).
      expect(find.text('BTC / USDT'), findsOneWidget);
      // Timeframe selector pills (chart-native timeframes replaced the
      // old 1H/1D/... range selector).
      expect(find.text('1m'), findsOneWidget);
      expect(find.text('1h'), findsOneWidget);
      // Purchase card lives below the chart; scroll it into view.
      await tester.scrollUntilVisible(
        find.text('Buy'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Buy'), findsOneWidget);
    });

    testWidgets('search filters the markets list', (WidgetTester tester) async {
      await tester.pumpWidget(_buildApp());
      await _pumpMicroTask(tester);

      final Finder field = find.widgetWithText(
        TextField,
        'Search tokens, pairs, or categories...',
      );
      expect(field, findsOneWidget);

      await tester.enterText(field, 'sol');
      await _pumpMicroTask(tester);

      expect(find.text('Solana'), findsOneWidget);
      expect(find.text('Bitcoin'), findsNothing);
    });
  });
}
