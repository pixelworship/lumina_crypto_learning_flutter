import 'dart:io';

import 'package:flutter_demo/data/models/fill.dart';
import 'package:flutter_demo/data/services/fill_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

DateTime _at(int hour) => DateTime.utc(2026, 5, 3, hour);

Fill _fill({
  required String symbol,
  required int hour,
  required double price,
  String id = 'fill-id',
  double sizeBase = 0.1,
  String quoteSymbol = 'USDT',
  FillSide side = FillSide.buy,
}) {
  return Fill(
    id: id,
    symbol: symbol,
    side: side,
    price: price,
    sizeBase: sizeBase,
    costQuote: price * sizeBase,
    quoteSymbol: quoteSymbol,
    timestamp: _at(hour),
  );
}

/// Mints a unique box name per test so parallel test isolation is
/// preserved (each test gets its own on-disk file).
int _boxCounter = 0;
String _nextBoxName() => 'fills_test_${_boxCounter++}';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('lumina_fill_storage_');
    Hive.init(tempDir.path);
    registerFillAdapters();
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('FillStorage', () {
    test('valuesFor returns empty list when nothing has been stored', () async {
      final FillStorage storage = await FillStorage.open(boxName: _nextBoxName());
      expect(storage.valuesFor('BTC'), isEmpty);
      await storage.close();
    });

    test('put + valuesFor round-trips a fill', () async {
      final FillStorage storage = await FillStorage.open(boxName: _nextBoxName());
      final Fill fill = _fill(symbol: 'BTC', hour: 1, price: 100, id: 'a');

      await storage.put(fill);

      final List<Fill> got = storage.valuesFor('BTC');
      expect(got, hasLength(1));
      expect(got.single, fill);
      await storage.close();
    });

    test('valuesFor is case-insensitive on the query symbol', () async {
      final FillStorage storage = await FillStorage.open(boxName: _nextBoxName());
      await storage.put(_fill(symbol: 'BTC', hour: 1, price: 100, id: 'a'));

      expect(storage.valuesFor('btc'), hasLength(1));
      expect(storage.valuesFor('BTC'), hasLength(1));
      await storage.close();
    });

    test('valuesFor sorts ascending by timestamp', () async {
      final FillStorage storage = await FillStorage.open(boxName: _nextBoxName());
      // Insert out of chronological order on purpose so the sort path
      // is what produces the final order.
      await storage.put(_fill(symbol: 'BTC', hour: 5, price: 100, id: 'c'));
      await storage.put(_fill(symbol: 'BTC', hour: 1, price: 100, id: 'a'));
      await storage.put(_fill(symbol: 'BTC', hour: 3, price: 100, id: 'b'));

      final List<int> hours = storage
          .valuesFor('BTC')
          .map((Fill f) => f.timestamp.hour)
          .toList();
      expect(hours, <int>[1, 3, 5]);
      await storage.close();
    });

    test('valuesFor scopes results to the requested symbol', () async {
      final FillStorage storage = await FillStorage.open(boxName: _nextBoxName());
      await storage.put(_fill(symbol: 'BTC', hour: 1, price: 100, id: 'a'));
      await storage.put(_fill(symbol: 'ETH', hour: 1, price: 100, id: 'b'));
      await storage.put(_fill(symbol: 'BTC', hour: 2, price: 110, id: 'c'));

      expect(storage.valuesFor('BTC').map((Fill f) => f.id), <String>['a', 'c']);
      expect(storage.valuesFor('ETH').map((Fill f) => f.id), <String>['b']);
      await storage.close();
    });

    test('put overwrites an existing fill with the same id', () async {
      final FillStorage storage = await FillStorage.open(boxName: _nextBoxName());
      await storage.put(_fill(symbol: 'BTC', hour: 1, price: 100, id: 'a'));
      await storage.put(_fill(symbol: 'BTC', hour: 1, price: 200, id: 'a'));

      final List<Fill> got = storage.valuesFor('BTC');
      expect(got, hasLength(1));
      expect(got.single.price, 200);
      await storage.close();
    });

    test('persisted fills survive box close + reopen', () async {
      final String boxName = _nextBoxName();
      final FillStorage first = await FillStorage.open(boxName: boxName);
      await first.put(_fill(symbol: 'BTC', hour: 1, price: 100, id: 'a'));
      await first.close();

      final FillStorage second = await FillStorage.open(boxName: boxName);
      expect(second.valuesFor('BTC'), hasLength(1));
      expect(second.valuesFor('BTC').single.id, 'a');
      await second.close();
    });

    test('FillSide adapter round-trips both enum values', () async {
      final FillStorage storage = await FillStorage.open(boxName: _nextBoxName());
      await storage.put(_fill(symbol: 'BTC', hour: 1, price: 100, id: 'b', side: FillSide.buy));
      await storage.put(_fill(symbol: 'BTC', hour: 2, price: 100, id: 's', side: FillSide.sell));

      final List<Fill> got = storage.valuesFor('BTC');
      expect(got.firstWhere((Fill f) => f.id == 'b').side, FillSide.buy);
      expect(got.firstWhere((Fill f) => f.id == 's').side, FillSide.sell);
      await storage.close();
    });

    test('clear drops every fill', () async {
      final FillStorage storage = await FillStorage.open(boxName: _nextBoxName());
      await storage.put(_fill(symbol: 'BTC', hour: 1, price: 100, id: 'a'));
      await storage.put(_fill(symbol: 'ETH', hour: 1, price: 100, id: 'b'));
      await storage.clear();
      expect(storage.all(), isEmpty);
      await storage.close();
    });
  });
}
