import 'dart:async';
import 'dart:io';

import 'package:flutter_demo/data/models/fill.dart';
import 'package:flutter_demo/data/models/tick.dart';
import 'package:flutter_demo/data/repositories/fill_repository.dart';
import 'package:flutter_demo/data/repositories/historical_tick_repository.dart';
import 'package:flutter_demo/data/repositories/tick_repository.dart';
import 'package:flutter_demo/data/repositories/trade_repository.dart';
import 'package:flutter_demo/data/services/asset_catalog.dart';
import 'package:flutter_demo/data/services/fill_storage.dart';
import 'package:flutter_demo/data/services/live_price_feed.dart';
import 'package:flutter_demo/presentation/blocs/chart/chart_bloc.dart';
import 'package:flutter_demo/presentation/blocs/chart/chart_event.dart';
import 'package:flutter_demo/presentation/blocs/trade/trade_bloc.dart';
import 'package:flutter_demo/presentation/blocs/trade/trade_event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';

class _MockTradeRepository extends Mock implements TradeRepository {}

class _MockTickRepository extends Mock implements TickRepository {}

class _MockHistoricalTickRepository extends Mock
    implements HistoricalTickRepository {}

/// End-to-end programmatic stand-in for the spec's manual QA pass.
///
/// Exercises the real path: `TradePurchaseSubmitted` → repository
/// accept → `FillRepository.recordFill` → Hive on disk → broadcast
/// stream → `ChartBloc` `_FillsUpdated` → `ChartState.fills`. Then
/// closes the bloc + repository, reopens the box from disk into a
/// fresh `LocalFillRepository`, and confirms the fill is still there.
///
/// If this test passes, the only thing left for human QA is to
/// confirm the marker glyph is rendered correctly — the data layer
/// round-trips end-to-end.
void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('lumina_e2e_fills_');
    Hive.init(tempDir.path);
    registerFillAdapters();
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('purchase → fill → ChartState.fills → cold-start replay', () async {
    final _MockTradeRepository tradeRepo = _MockTradeRepository();
    when(
      () => tradeRepo.purchase(
        fromSymbol: any(named: 'fromSymbol'),
        toSymbol: any(named: 'toSymbol'),
        amount: any(named: 'amount'),
      ),
    ).thenAnswer((_) async => true);

    final LivePriceFeed priceFeed = LivePriceFeed(
      catalog: StaticAssetCatalog(),
      startPaused: true,
    );

    final FillStorage storage =
        await FillStorage.open(boxName: 'e2e_test_box');
    final LocalFillRepository fillRepo =
        LocalFillRepository(storage: storage);

    final _MockTickRepository tickRepo = _MockTickRepository();
    final StreamController<Tick> tickStream =
        StreamController<Tick>.broadcast();
    when(() => tickRepo.watchTicks(any()))
        .thenAnswer((_) => tickStream.stream);
    final _MockHistoricalTickRepository historicalRepo =
        _MockHistoricalTickRepository();
    when(
      () => historicalRepo.fetchTicks(
        symbol: any(named: 'symbol'),
        start: any(named: 'start'),
        end: any(named: 'end'),
      ),
    ).thenAnswer((_) async => const <Tick>[]);
    when(
      () => historicalRepo.peekTicks(
        symbol: any(named: 'symbol'),
        start: any(named: 'start'),
        end: any(named: 'end'),
      ),
    ).thenReturn(const <Tick>[]);

    final ChartBloc chartBloc = ChartBloc(
      repository: tickRepo,
      historicalRepository: historicalRepo,
      fillRepository: fillRepo,
      initialSymbol: 'BTC',
    );
    final TradeBloc tradeBloc = TradeBloc(
      tradeRepository: tradeRepo,
      priceFeed: priceFeed,
      fillRepository: fillRepo,
      idGenerator: () => 'e2e-fill-1',
    );

    chartBloc.add(const ChartStarted(symbol: 'BTC'));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(chartBloc.state.fills, isEmpty);

    tradeBloc.add(
      const TradePurchaseSubmitted(
        fromSymbol: 'USDT',
        toSymbol: 'BTC',
        amount: 0.1,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 60));

    expect(
      chartBloc.state.fills.map((Fill f) => f.id),
      <String>['e2e-fill-1'],
      reason: 'fill should propagate from TradeBloc → repo → ChartBloc',
    );
    expect(chartBloc.state.fills.single.symbol, 'BTC');
    expect(chartBloc.state.fills.single.sizeBase, 0.1);

    await chartBloc.close();
    await tradeBloc.close();
    await fillRepo.dispose();
    await storage.close();
    await tickStream.close();
    await priceFeed.dispose();

    // ── Cold-start replay ─────────────────────────────────────────
    final FillStorage storage2 =
        await FillStorage.open(boxName: 'e2e_test_box');
    final LocalFillRepository fillRepo2 =
        LocalFillRepository(storage: storage2);
    final List<Fill> persisted = await fillRepo2.getFills('BTC');
    expect(persisted, hasLength(1));
    expect(persisted.single.id, 'e2e-fill-1');
    await fillRepo2.dispose();
    await storage2.close();
  });
}
