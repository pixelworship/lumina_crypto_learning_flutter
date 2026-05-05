import 'package:flutter/material.dart';
import 'package:flutter_demo/data/models/asset_category.dart';
import 'package:flutter_demo/data/models/balance_summary.dart';
import 'package:flutter_demo/data/models/crypto_asset.dart';
import 'package:flutter_demo/data/models/order_book_entry.dart';
import 'package:flutter_demo/data/models/portfolio_holding.dart';
import 'package:flutter_demo/data/models/price_point.dart';
import 'package:flutter_demo/data/models/trade_pair_snapshot.dart';

/// Compact, deterministic fixtures used across unit tests.
///
/// Keeping these in one place lets us:
///   * avoid leaking real `LuminaPalette` colors into test files,
///   * exercise enough categories to test filtering paths,
///   * snapshot stable values so test diffs stay meaningful.
class TestAssets {
  TestAssets._();

  static const CryptoAsset btc = CryptoAsset(
    id: 'btc',
    symbol: 'BTC',
    name: 'Bitcoin',
    color: Color(0xFFF7931A),
    iconLetter: 'B',
    categories: <AssetCategory>[AssetCategory.layer1],
  );

  static const CryptoAsset eth = CryptoAsset(
    id: 'eth',
    symbol: 'ETH',
    name: 'Ethereum',
    color: Color(0xFF627EEA),
    iconLetter: 'E',
    categories: <AssetCategory>[AssetCategory.layer1, AssetCategory.defi],
  );

  static const CryptoAsset uni = CryptoAsset(
    id: 'uni',
    symbol: 'UNI',
    name: 'Uniswap',
    color: Color(0xFFFF007A),
    iconLetter: 'U',
    categories: <AssetCategory>[AssetCategory.defi],
  );

  static const CryptoAsset usdt = CryptoAsset(
    id: 'usdt',
    symbol: 'USDT',
    name: 'Tether',
    color: Color(0xFF26A17B),
    iconLetter: 'T',
    categories: <AssetCategory>[AssetCategory.stablecoin],
  );

  static const List<CryptoAsset> all = <CryptoAsset>[btc, eth, uni, usdt];

  static const CryptoQuote btcQuote = CryptoQuote(
    asset: btc,
    rank: 1,
    price: 64000,
    change24hPercent: 2.4,
    change24hAbsolute: 1500,
    priceAt24hAgo: 62500,
  );

  static const CryptoQuote ethQuote = CryptoQuote(
    asset: eth,
    rank: 2,
    price: 3450,
    change24hPercent: -1.2,
    change24hAbsolute: -42,
    priceAt24hAgo: 3492,
  );

  static const CryptoQuote uniQuote = CryptoQuote(
    asset: uni,
    rank: 4,
    price: 11.0,
    change24hPercent: 0.5,
    change24hAbsolute: 0.05,
    priceAt24hAgo: 10.95,
  );

  static const List<CryptoQuote> watchlist = <CryptoQuote>[btcQuote, ethQuote];

  static final BalanceSummary balance = BalanceSummary(
    totalBalanceUsd: 142850.24,
    change24hUsd: 3420.50,
    change24hPercent: 2.4,
    valueAt24hAgo: 139429.74,
    sparkline: <PricePoint>[
      PricePoint(timestamp: DateTime.utc(2026, 1, 1), price: 100),
      PricePoint(timestamp: DateTime.utc(2026, 1, 2), price: 110),
    ],
  );

  static const PortfolioSummary portfolio = PortfolioSummary(
    totalValueUsd: 124850.42,
    changeTodayUsd: 3420.50,
    changeTodayPercent: 2.8,
    totalValueAt24hAgo: 121429.92,
    holdings: <PortfolioHolding>[
      PortfolioHolding(
        asset: btc,
        quantity: 1.2168,
        currentPrice: 64230.50,
        costBasisPerUnit: 51343.42,
        allocationPercent: 50,
      ),
      PortfolioHolding(
        asset: eth,
        quantity: 10.85,
        currentPrice: 3450.12,
        costBasisPerUnit: 2895.10,
        allocationPercent: 50,
      ),
    ],
  );

  static final TradePairSnapshot tradePair = TradePairSnapshot(
    base: btc,
    quote: usdt,
    price: 64289.50,
    changePercent: 2.46,
    priceAt24hAgo: 62745.22,
    range: ChartRange.oneDay,
    priceHistory: <PricePoint>[
      PricePoint(timestamp: DateTime.utc(2026, 1, 1), price: 63000),
      PricePoint(timestamp: DateTime.utc(2026, 1, 2), price: 64289.50),
    ],
    bids: const <OrderBookEntry>[
      OrderBookEntry(price: 64289, amount: 1.0, side: OrderSide.bid),
    ],
    asks: const <OrderBookEntry>[
      OrderBookEntry(price: 64290, amount: 1.0, side: OrderSide.ask),
    ],
  );
}
