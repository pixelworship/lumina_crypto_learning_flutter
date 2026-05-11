import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'data/repositories/chart_events_repository.dart';
import 'data/repositories/fill_repository.dart';
import 'data/repositories/historical_tick_repository.dart';
import 'data/repositories/market_repository.dart';
import 'data/repositories/portfolio_repository.dart';
import 'data/repositories/tick_repository.dart';
import 'data/repositories/trade_repository.dart';
import 'data/services/api_service.dart';
import 'data/services/asset_catalog.dart';
import 'data/services/chart_events_api.dart';
import 'data/services/historical_price_api.dart';
import 'data/services/historical_tick_cache.dart';
import 'data/services/live_price_feed.dart';
import 'data/services/mock_api_service.dart';
import 'data/services/sparkline_feed.dart';
import 'design_system/lumina_ui.dart';
import 'presentation/blocs/debug/sparkline_open_line_cubit.dart';
import 'presentation/blocs/home/home_bloc.dart';
import 'presentation/blocs/markets/markets_bloc.dart';
import 'presentation/blocs/navigation/navigation_cubit.dart';
import 'presentation/blocs/portfolio/portfolio_bloc.dart';
import 'presentation/screens/main_shell.dart';

/// Root widget that provides repositories + BLoCs to the rest of the tree.
///
/// Theme switching is handled here: a [ThemeModeCubit] drives
/// [MaterialApp.themeMode] and the design system's tokens flow
/// automatically.
///
/// Tests can pass [apiOverride] to substitute a fake [ApiService] without
/// touching anything else in the widget tree, and [startChartStreaming]
/// to disable the live tick stream (which would otherwise prevent
/// `pumpAndSettle` from ever returning).
///
/// Per-asset `TradeBloc` and `ChartBloc` instances are NOT provided here —
/// they live for the lifetime of an `AssetDetailScreen` route, so each
/// detail page is a fresh, isolated experience seeded with its own symbol.
class LuminaApp extends StatelessWidget {
  const LuminaApp({
    super.key,
    ApiService? apiOverride,
    FillRepository? fillRepositoryOverride,
    this.startChartStreaming = true,
  }) : _apiOverride = apiOverride,
       _fillRepositoryOverride = fillRepositoryOverride;

  final ApiService? _apiOverride;

  /// Optional pre-built fill repository. Production wiring (in
  /// `main.dart`) opens a Hive box and passes a [LocalFillRepository]
  /// here; widget tests omit this parameter and the build method
  /// falls back to an [InMemoryFillRepository] so the test tree
  /// doesn't need to bootstrap Hive.
  final FillRepository? _fillRepositoryOverride;

  /// When false, the chart's live tick stream is not started on app
  /// boot. Used by widget tests so animation drivers don't keep
  /// rebuilding forever.
  final bool startChartStreaming;

  @override
  Widget build(BuildContext context) {
    // The LivePriceFeed is the single source of truth for prices in
    // the app. It's injected into the api service so market quotes,
    // portfolio holdings, trade snapshots, etc. all read live prices,
    // and into the chart's tick repositories so the candlestick chart
    // for an asset reflects the same number that asset's row in the
    // markets list shows.
    //
    // When `startChartStreaming` is false (typically in widget tests)
    // the feed is constructed paused so its periodic timer doesn't
    // keep `pumpAndSettle` alive forever. Synchronous reads via
    // [LivePriceFeed.currentPrice] still work — the price map is
    // seeded at construction.
    final AssetCatalog catalog = StaticAssetCatalog();
    final LivePriceFeed priceFeed = LivePriceFeed(
      catalog: catalog,
      startPaused: !startChartStreaming,
    );
    final ApiService api =
        _apiOverride ?? MockApiService(catalog: catalog, priceFeed: priceFeed);

    // The historical data path is intentionally separate from the
    // live feed: a stateless date-range API + an in-memory cache
    // that holds the top 50 recently-viewed symbols × the last
    // ~2 days of data per symbol. Repository plays facade over both
    // so callers see a single `fetchTicks` entry point.
    //
    // When `startChartStreaming` is false (test mode) we drop the
    // simulated latency to zero so widget tests that push the asset
    // detail route don't leave a `Future.delayed` hanging in the
    // pending-timer set.
    final HistoricalPriceApi historicalApi = MockHistoricalPriceApi(
      feed: priceFeed,
      latency: startChartStreaming
          ? const Duration(milliseconds: 250)
          : Duration.zero,
    );
    final HistoricalTickCache historicalCache = HistoricalTickCache();

    // Per-asset live mini-sparklines for the markets + watchlist
    // rows. Owns one rolling buffer per symbol; subscribes once to
    // the price feed and broadcasts row-local updates via
    // ValueListenable so per-row repaints stay surgical. The
    // initial 24h shape is seeded from the warehouse api (same
    // surface the candlestick chart pulls from), with the same
    // 250ms latency baked in — rows render a shimmer placeholder
    // until the response resolves.
    final SparklineFeed sparklineFeed = SparklineFeed(
      feed: priceFeed,
      historicalApi: historicalApi,
    );

    // User fills (executed purchases). Production main wires a
    // Hive-backed [LocalFillRepository] via the override; widget
    // tests fall back to a volatile in-memory shim so they don't
    // need to spin up Hive on disk.
    final FillRepository fillRepository =
        _fillRepositoryOverride ?? InMemoryFillRepository();

    return MultiRepositoryProvider(
      providers: <RepositoryProvider<dynamic>>[
        RepositoryProvider<ApiService>(create: (_) => api),
        RepositoryProvider<AssetCatalog>(create: (_) => catalog),
        RepositoryProvider<LivePriceFeed>(
          create: (_) => priceFeed,
          dispose: (LivePriceFeed feed) => feed.dispose(),
        ),
        RepositoryProvider<HistoricalPriceApi>(create: (_) => historicalApi),
        RepositoryProvider<HistoricalTickCache>(create: (_) => historicalCache),
        RepositoryProvider<SparklineFeed>(
          create: (_) => sparklineFeed,
          dispose: (SparklineFeed feed) => feed.dispose(),
        ),
        RepositoryProvider<MarketRepository>(
          create: (_) => MockMarketRepository(api),
        ),
        RepositoryProvider<PortfolioRepository>(
          create: (_) => MockPortfolioRepository(api),
        ),
        RepositoryProvider<TradeRepository>(
          create: (_) => MockTradeRepository(api),
        ),
        RepositoryProvider<TickRepository>(
          create: (BuildContext ctx) =>
              MockTickRepository(feed: ctx.read<LivePriceFeed>()),
          dispose: (TickRepository repo) => repo.dispose(),
        ),
        RepositoryProvider<HistoricalTickRepository>(
          create: (BuildContext ctx) => CachedHistoricalTickRepository(
            api: ctx.read<HistoricalPriceApi>(),
            cache: ctx.read<HistoricalTickCache>(),
          ),
        ),

        // Chart events come from the deployed CDK stack in `_x/cdk`
        // (API Gateway + Lambdas + Supabase). The `_x/api` Express
        // server is a local-dev fallback that hits the same Supabase
        // table — point at it during dev with:
        //
        //   --dart-define=EVENTS_API_BASE_URL=http://localhost:4001
        //   --dart-define=EVENTS_API_BASE_URL=http://10.0.2.2:4001  (Android emulator)
        //
        // The trailing slash on the deployed URL is fine — the API
        // client trims it before composing request URIs.
        RepositoryProvider<ChartEventsApi>(
          create: (_) => HttpChartEventsApi(
            baseUrl: const String.fromEnvironment(
              'EVENTS_API_BASE_URL',
              defaultValue:
                  'https://lgrkbb3msg.execute-api.us-west-2.amazonaws.com/prod/',
            ),
          ),
        ),
        RepositoryProvider<ChartEventsRepository>(
          create: (BuildContext ctx) =>
              ChartEventsRepository(api: ctx.read<ChartEventsApi>()),
        ),
        RepositoryProvider<FillRepository>(
          create: (_) => fillRepository,
          dispose: (FillRepository repo) => repo.dispose(),
        ),
      ],
      child: MultiBlocProvider(
        providers: <BlocProvider<dynamic>>[
          BlocProvider<ThemeModeCubit>(
            create: (BuildContext context) => ThemeModeCubit(),
          ),
          BlocProvider<NavigationCubit>(
            create: (BuildContext context) => NavigationCubit(),
          ),
          BlocProvider<SparklineOpenLineCubit>(
            create: (BuildContext context) => SparklineOpenLineCubit(),
          ),
          BlocProvider<HomeBloc>(
            create: (BuildContext context) => HomeBloc(
              portfolioRepository: context.read<PortfolioRepository>(),
              marketRepository: context.read<MarketRepository>(),
              priceFeed: context.read<LivePriceFeed>(),
            ),
          ),
          BlocProvider<MarketsBloc>(
            create: (BuildContext context) => MarketsBloc(
              marketRepository: context.read<MarketRepository>(),
              priceFeed: context.read<LivePriceFeed>(),
            ),
          ),
          BlocProvider<PortfolioBloc>(
            create: (BuildContext context) => PortfolioBloc(
              portfolioRepository: context.read<PortfolioRepository>(),
              priceFeed: context.read<LivePriceFeed>(),
            ),
          ),
        ],
        child: BlocBuilder<ThemeModeCubit, ThemeMode>(
          builder: (BuildContext context, ThemeMode themeMode) {
            return MaterialApp(
              title: 'Lumina Crypto',
              debugShowCheckedModeBanner: false,
              theme: LuminaTheme.light(),
              darkTheme: LuminaTheme.dark(),
              themeMode: themeMode,
              home: const MainShell(),
            );
          },
        ),
      ),
    );
  }
}
