import 'package:flutter_demo/data/models/crypto_asset.dart';
import 'package:flutter_demo/data/services/asset_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/test_assets.dart';

void main() {
  group('StaticAssetCatalog', () {
    group('default catalog', () {
      late StaticAssetCatalog catalog;

      setUp(() {
        catalog = StaticAssetCatalog();
      });

      test('exposes a non-empty asset list', () {
        expect(catalog.all(), isNotEmpty);
      });

      test('all() returns an unmodifiable view', () {
        final List<CryptoAsset> assets = catalog.all();
        expect(
          () => assets.add(TestAssets.btc),
          throwsA(isA<UnsupportedError>()),
        );
      });

      test('contains the headline assets we ship with', () {
        final List<String> symbols = catalog
            .all()
            .map((CryptoAsset a) => a.symbol)
            .toList();
        expect(symbols, containsAll(<String>['BTC', 'ETH', 'SOL', 'USDT']));
      });

      test('every asset has a unique id', () {
        final Iterable<String> ids = catalog.all().map((CryptoAsset a) => a.id);
        expect(ids.toSet().length, ids.length);
      });

      test('every asset has a unique symbol', () {
        final Iterable<String> symbols = catalog
            .all()
            .map((CryptoAsset a) => a.symbol);
        expect(symbols.toSet().length, symbols.length);
      });
    });

    group('findBySymbol', () {
      late StaticAssetCatalog catalog;

      setUp(() {
        catalog = StaticAssetCatalog(TestAssets.all);
      });

      test('returns the asset for a known symbol', () {
        expect(catalog.findBySymbol('BTC'), TestAssets.btc);
        expect(catalog.findBySymbol('ETH'), TestAssets.eth);
      });

      test('is case-insensitive', () {
        expect(catalog.findBySymbol('btc'), TestAssets.btc);
        expect(catalog.findBySymbol('eth'), TestAssets.eth);
        expect(catalog.findBySymbol('UsDt'), TestAssets.usdt);
      });

      test('returns null for unknown symbols', () {
        expect(catalog.findBySymbol('XRP'), isNull);
        expect(catalog.findBySymbol(''), isNull);
      });
    });

    test('respects a custom asset list when provided', () {
      final StaticAssetCatalog catalog = StaticAssetCatalog(<CryptoAsset>[
        TestAssets.btc,
      ]);
      expect(catalog.all(), <CryptoAsset>[TestAssets.btc]);
      expect(catalog.findBySymbol('ETH'), isNull);
    });
  });
}
