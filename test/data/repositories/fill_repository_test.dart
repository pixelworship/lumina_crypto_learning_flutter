import 'dart:async';
import 'dart:io';

import 'package:flutter_demo/data/models/fill.dart';
import 'package:flutter_demo/data/repositories/fill_repository.dart';
import 'package:flutter_demo/data/services/fill_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

DateTime _at(int hour) => DateTime.utc(2026, 5, 3, hour);

Fill _fill({
  required String id,
  required String symbol,
  required int hour,
  double price = 100,
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

int _boxCounter = 0;
String _nextBoxName() => 'fills_repo_test_${_boxCounter++}';

Future<({FillStorage storage, LocalFillRepository repo})> _newRepo() async {
  final FillStorage storage = await FillStorage.open(boxName: _nextBoxName());
  final LocalFillRepository repo = LocalFillRepository(storage: storage);
  return (storage: storage, repo: repo);
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('lumina_fill_repo_');
    Hive.init(tempDir.path);
    registerFillAdapters();
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('LocalFillRepository', () {
    test('getFills returns empty list before any record', () async {
      final ({FillStorage storage, LocalFillRepository repo}) bundle =
          await _newRepo();
      final List<Fill> got = await bundle.repo.getFills('BTC');
      expect(got, isEmpty);
      await bundle.repo.dispose();
      await bundle.storage.close();
    });

    test('recordFill persists + appears in subsequent getFills', () async {
      final ({FillStorage storage, LocalFillRepository repo}) bundle =
          await _newRepo();
      await bundle.repo
          .recordFill(_fill(id: 'a', symbol: 'BTC', hour: 1, price: 100));

      final List<Fill> got = await bundle.repo.getFills('BTC');
      expect(got, hasLength(1));
      expect(got.single.id, 'a');
      await bundle.repo.dispose();
      await bundle.storage.close();
    });

    test('getFills is case-insensitive on symbol', () async {
      final ({FillStorage storage, LocalFillRepository repo}) bundle =
          await _newRepo();
      await bundle.repo
          .recordFill(_fill(id: 'a', symbol: 'BTC', hour: 1, price: 100));

      expect(await bundle.repo.getFills('btc'), hasLength(1));
      expect(await bundle.repo.getFills('BTC'), hasLength(1));
      await bundle.repo.dispose();
      await bundle.storage.close();
    });

    test('recorded fills land in the on-disk box', () async {
      final ({FillStorage storage, LocalFillRepository repo}) bundle =
          await _newRepo();
      await bundle.repo
          .recordFill(_fill(id: 'a', symbol: 'BTC', hour: 1, price: 100));

      expect(bundle.storage.valuesFor('BTC'), hasLength(1));
      await bundle.repo.dispose();
      await bundle.storage.close();
    });

    test('watchFills replays the current snapshot to a new subscriber',
        () async {
      final ({FillStorage storage, LocalFillRepository repo}) bundle =
          await _newRepo();
      await bundle.repo
          .recordFill(_fill(id: 'a', symbol: 'BTC', hour: 1, price: 100));

      final List<Fill> first = await bundle.repo.watchFills('BTC').first;
      expect(first.map((Fill f) => f.id), <String>['a']);
      await bundle.repo.dispose();
      await bundle.storage.close();
    });

    test('watchFills broadcasts updates when recordFill lands', () async {
      final ({FillStorage storage, LocalFillRepository repo}) bundle =
          await _newRepo();

      final List<List<Fill>> received = <List<Fill>>[];
      final StreamSubscription<List<Fill>> sub = bundle.repo
          .watchFills('BTC')
          .listen(received.add);

      // Allow the replay-of-initial event to flush, then add fills.
      await Future<void>.delayed(Duration.zero);
      await bundle.repo
          .recordFill(_fill(id: 'a', symbol: 'BTC', hour: 1, price: 100));
      await bundle.repo
          .recordFill(_fill(id: 'b', symbol: 'BTC', hour: 2, price: 110));

      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      // [empty (replay), [a], [a, b]]
      expect(received.length, greaterThanOrEqualTo(3));
      expect(received.first, isEmpty);
      expect(received[1].map((Fill f) => f.id), <String>['a']);
      expect(received[2].map((Fill f) => f.id), <String>['a', 'b']);
      await bundle.repo.dispose();
      await bundle.storage.close();
    });

    test('watchFills only sees updates for the matching symbol', () async {
      final ({FillStorage storage, LocalFillRepository repo}) bundle =
          await _newRepo();

      final List<List<Fill>> btcEvents = <List<Fill>>[];
      final StreamSubscription<List<Fill>> sub = bundle.repo
          .watchFills('BTC')
          .listen(btcEvents.add);

      await Future<void>.delayed(Duration.zero);
      await bundle.repo
          .recordFill(_fill(id: 'eth-a', symbol: 'ETH', hour: 1, price: 100));
      await Future<void>.delayed(Duration.zero);

      // ETH fills must not produce BTC events beyond the initial empty
      // replay (0 or 1 events depending on test timing — we assert the
      // BTC watcher never sees an ETH fill).
      for (final List<Fill> snapshot in btcEvents) {
        for (final Fill f in snapshot) {
          expect(f.symbol, 'BTC');
        }
      }
      await sub.cancel();
      await bundle.repo.dispose();
      await bundle.storage.close();
    });

    test('recordFill with a duplicate id overwrites the existing fill',
        () async {
      final ({FillStorage storage, LocalFillRepository repo}) bundle =
          await _newRepo();
      await bundle.repo
          .recordFill(_fill(id: 'a', symbol: 'BTC', hour: 1, price: 100));
      await bundle.repo
          .recordFill(_fill(id: 'a', symbol: 'BTC', hour: 1, price: 200));

      final List<Fill> got = await bundle.repo.getFills('BTC');
      expect(got, hasLength(1));
      expect(got.single.price, 200);
      await bundle.repo.dispose();
      await bundle.storage.close();
    });

    test('fills survive repository teardown when re-created against same '
        'storage box', () async {
      final String box = _nextBoxName();
      final FillStorage storage = await FillStorage.open(boxName: box);
      final LocalFillRepository first = LocalFillRepository(storage: storage);
      await first
          .recordFill(_fill(id: 'a', symbol: 'BTC', hour: 1, price: 100));
      await first.dispose();
      await storage.close();

      final FillStorage storage2 = await FillStorage.open(boxName: box);
      final LocalFillRepository second = LocalFillRepository(storage: storage2);
      final List<Fill> got = await second.getFills('BTC');
      expect(got, hasLength(1));
      expect(got.single.id, 'a');
      await second.dispose();
      await storage2.close();
    });
  });
}
