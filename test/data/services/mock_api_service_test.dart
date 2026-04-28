import 'dart:math';

import 'package:flutter_demo/core/clock/clock.dart';
import 'package:flutter_demo/data/models/balance_summary.dart';
import 'package:flutter_demo/data/models/crypto_asset.dart';
import 'package:flutter_demo/data/models/order_book_entry.dart';
import 'package:flutter_demo/data/models/portfolio_holding.dart';
import 'package:flutter_demo/data/models/price_point.dart';
import 'package:flutter_demo/data/models/trade_pair_snapshot.dart';
import 'package:flutter_demo/data/services/asset_catalog.dart';
import 'package:flutter_demo/data/services/mock_api_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeClock clock;
  late MockApiService api;

  setUp(() {
    clock = FakeClock(DateTime.utc(2026, 1, 1, 12));
    api = MockApiService(
      latency: Duration.zero,
      clock: clock,
      catalog: StaticAssetCatalog(),
      random: Random(42),
    );
  });

  group('MockApiService.fetchMarketQuotes', () {
    test('returns a non-empty list of quotes', () async {
      final List<CryptoQuote> quotes = await api.fetchMarketQuotes();
      expect(quotes, isNotEmpty);
    });

    test('quotes are ranked starting from 1 in ascending order', () async {
      final List<CryptoQuote> quotes = await api.fetchMarketQuotes();
      expect(quotes.first.rank, 1);
      for (int i = 1; i < quotes.length; i++) {
        expect(
          quotes[i].rank,
          greaterThan(quotes[i - 1].rank),
          reason: 'rank must strictly increase',
        );
      }
    });

    test('every quote refers to an asset present in the catalog', () async {
      final StaticAssetCatalog catalog = StaticAssetCatalog();
      final List<CryptoQuote> quotes = await api.fetchMarketQuotes();
      for (final CryptoQuote q in quotes) {
        expect(catalog.findBySymbol(q.asset.symbol), q.asset);
      }
    });

    test('returns the same data on repeated calls (deterministic)', () async {
      final List<CryptoQuote> first = await api.fetchMarketQuotes();
      final List<CryptoQuote> second = await api.fetchMarketQuotes();
      expect(first, second);
    });
  });

  group('MockApiService.fetchWatchlist', () {
    test('returns a subset of fetchMarketQuotes', () async {
      final List<CryptoQuote> all = await api.fetchMarketQuotes();
      final List<CryptoQuote> watchlist = await api.fetchWatchlist();

      expect(watchlist.length, lessThan(all.length));
      for (final CryptoQuote w in watchlist) {
        expect(all, contains(w));
      }
    });

    test('contains the canonical watched assets', () async {
      final List<CryptoQuote> watchlist = await api.fetchWatchlist();
      final Set<String> ids = watchlist
          .map((CryptoQuote q) => q.asset.id)
          .toSet();
      expect(ids, <String>{'btc', 'eth', 'sol', 'avax'});
    });
  });

  group('MockApiService.fetchBalanceSummary', () {
    test('returns a non-empty sparkline anchored to the fake clock', () async {
      final BalanceSummary summary = await api.fetchBalanceSummary();

      expect(summary.sparkline, isNotEmpty);
      expect(summary.sparkline.last.timestamp, clock.now());
    });

    test(
      'sparkline timestamps are monotonically non-decreasing',
      () async {
        final BalanceSummary summary = await api.fetchBalanceSummary();
        for (int i = 1; i < summary.sparkline.length; i++) {
          expect(
            summary.sparkline[i].timestamp.isBefore(
              summary.sparkline[i - 1].timestamp,
            ),
            isFalse,
          );
        }
      },
    );

    test('sparkline ends exactly at totalBalanceUsd', () async {
      final BalanceSummary summary = await api.fetchBalanceSummary();
      expect(summary.sparkline.last.price, 142850.0);
    });

    test('respects clock advancement between calls', () async {
      final BalanceSummary first = await api.fetchBalanceSummary();
      clock.advance(const Duration(hours: 6));
      final BalanceSummary second = await api.fetchBalanceSummary();

      expect(
        second.sparkline.last.timestamp,
        first.sparkline.last.timestamp.add(const Duration(hours: 6)),
      );
    });
  });

  group('MockApiService.fetchPortfolio', () {
    test('returns holdings whose allocations sum to ~100%', () async {
      final PortfolioSummary summary = await api.fetchPortfolio();
      final double total = summary.holdings.fold<double>(
        0.0,
        (double sum, PortfolioHolding h) => sum + h.allocationPercent,
      );
      expect(total, closeTo(100.0, 0.01));
    });

    test('every holding has a positive market value', () async {
      final PortfolioSummary summary = await api.fetchPortfolio();
      for (final PortfolioHolding h in summary.holdings) {
        expect(h.marketValue, greaterThan(0));
      }
    });

    test('exposes an asset count matching the holdings list', () async {
      final PortfolioSummary summary = await api.fetchPortfolio();
      expect(summary.assetCount, summary.holdings.length);
    });
  });

  group('MockApiService.fetchTradePair', () {
    test('returns the requested base/quote pair', () async {
      final TradePairSnapshot snap = await api.fetchTradePair(
        baseSymbol: 'eth',
        quoteSymbol: 'usdt',
        range: ChartRange.oneHour,
      );
      expect(snap.base.symbol, 'ETH');
      expect(snap.quote.symbol, 'USDT');
      expect(snap.range, ChartRange.oneHour);
    });

    test('produces denser histories for longer ranges', () async {
      final TradePairSnapshot oneHour = await api.fetchTradePair(
        baseSymbol: 'BTC',
        quoteSymbol: 'USDT',
        range: ChartRange.oneHour,
      );
      final TradePairSnapshot oneDay = await api.fetchTradePair(
        baseSymbol: 'BTC',
        quoteSymbol: 'USDT',
        range: ChartRange.oneDay,
      );

      expect(oneDay.priceHistory.length, greaterThan(oneHour.priceHistory.length));
    });

    test('history ends with the snapshot price', () async {
      final TradePairSnapshot snap = await api.fetchTradePair(
        baseSymbol: 'BTC',
        quoteSymbol: 'USDT',
        range: ChartRange.oneDay,
      );
      expect(snap.priceHistory.last.price, snap.price);
    });

    test('throws ArgumentError for unknown base symbol', () {
      expect(
        () => api.fetchTradePair(
          baseSymbol: 'XYZ',
          quoteSymbol: 'USDT',
          range: ChartRange.oneDay,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError for unknown quote symbol', () {
      expect(
        () => api.fetchTradePair(
          baseSymbol: 'BTC',
          quoteSymbol: 'XYZ',
          range: ChartRange.oneDay,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('returns balanced bids and asks', () async {
      final TradePairSnapshot snap = await api.fetchTradePair(
        baseSymbol: 'BTC',
        quoteSymbol: 'USDT',
        range: ChartRange.oneDay,
      );

      expect(snap.bids, isNotEmpty);
      expect(snap.asks, isNotEmpty);
      for (final OrderBookEntry b in snap.bids) {
        expect(b.side, OrderSide.bid);
      }
      for (final OrderBookEntry a in snap.asks) {
        expect(a.side, OrderSide.ask);
      }
      expect(snap.bids.first.price, lessThan(snap.asks.first.price));
    });

    test('history timestamps are anchored to the fake clock', () async {
      final TradePairSnapshot snap = await api.fetchTradePair(
        baseSymbol: 'BTC',
        quoteSymbol: 'USDT',
        range: ChartRange.oneDay,
      );
      expect(snap.priceHistory.last.timestamp, clock.now());
    });
  });

  group('MockApiService.submitSwap', () {
    test('returns true for a valid swap', () async {
      final bool ok = await api.submitSwap(
        fromSymbol: 'BTC',
        toSymbol: 'USDT',
        amount: 0.5,
      );
      expect(ok, isTrue);
    });

    test('returns false for non-positive amounts', () async {
      expect(
        await api.submitSwap(fromSymbol: 'BTC', toSymbol: 'USDT', amount: 0),
        isFalse,
      );
      expect(
        await api.submitSwap(fromSymbol: 'BTC', toSymbol: 'USDT', amount: -1),
        isFalse,
      );
    });

    test('returns false when either symbol is unknown', () async {
      expect(
        await api.submitSwap(fromSymbol: 'XYZ', toSymbol: 'USDT', amount: 0.5),
        isFalse,
      );
      expect(
        await api.submitSwap(fromSymbol: 'BTC', toSymbol: 'XYZ', amount: 0.5),
        isFalse,
      );
    });
  });

  group('MockApiService.submitDeposit / submitWithdrawal', () {
    test('returns true for positive amounts', () async {
      expect(await api.submitDeposit(amountUsd: 100), isTrue);
      expect(await api.submitWithdrawal(amountUsd: 100), isTrue);
    });

    test('returns false for non-positive amounts', () async {
      expect(await api.submitDeposit(amountUsd: 0), isFalse);
      expect(await api.submitDeposit(amountUsd: -50), isFalse);
      expect(await api.submitWithdrawal(amountUsd: 0), isFalse);
      expect(await api.submitWithdrawal(amountUsd: -50), isFalse);
    });
  });

  group('PriceHistory determinism', () {
    test('two services with the same seed produce identical histories', () async {
      final FakeClock clockA = FakeClock(DateTime.utc(2026));
      final FakeClock clockB = FakeClock(DateTime.utc(2026));
      final MockApiService a = MockApiService(
        latency: Duration.zero,
        clock: clockA,
        seed: 99,
      );
      final MockApiService b = MockApiService(
        latency: Duration.zero,
        clock: clockB,
        seed: 99,
      );

      final TradePairSnapshot snapA = await a.fetchTradePair(
        baseSymbol: 'BTC',
        quoteSymbol: 'USDT',
        range: ChartRange.oneDay,
      );
      final TradePairSnapshot snapB = await b.fetchTradePair(
        baseSymbol: 'BTC',
        quoteSymbol: 'USDT',
        range: ChartRange.oneDay,
      );

      final List<double> pricesA = snapA.priceHistory
          .map((PricePoint p) => p.price)
          .toList();
      final List<double> pricesB = snapB.priceHistory
          .map((PricePoint p) => p.price)
          .toList();

      expect(pricesA, pricesB);
    });
  });
}
