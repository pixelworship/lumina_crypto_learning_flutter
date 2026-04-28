import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'data/repositories/market_repository.dart';
import 'data/repositories/portfolio_repository.dart';
import 'data/repositories/trade_repository.dart';
import 'data/services/api_service.dart';
import 'data/services/mock_api_service.dart';
import 'design_system/lumina_ui.dart';
import 'presentation/blocs/home/home_bloc.dart';
import 'presentation/blocs/markets/markets_bloc.dart';
import 'presentation/blocs/navigation/navigation_cubit.dart';
import 'presentation/blocs/portfolio/portfolio_bloc.dart';
import 'presentation/blocs/trade/trade_bloc.dart';
import 'presentation/screens/main_shell.dart';

/// Root widget that provides repositories + BLoCs to the rest of the tree.
///
/// Theme switching is handled here: a [ThemeModeCubit] drives
/// [MaterialApp.themeMode] and the design system's tokens flow automatically.
///
/// Tests can pass [apiOverride] to substitute a fake [ApiService] without
/// touching anything else in the widget tree.
class LuminaApp extends StatelessWidget {
  const LuminaApp({super.key, ApiService? apiOverride})
    : _apiOverride = apiOverride;

  final ApiService? _apiOverride;

  @override
  Widget build(BuildContext context) {
    final ApiService api = _apiOverride ?? MockApiService();

    return MultiRepositoryProvider(
      providers: <RepositoryProvider<dynamic>>[
        RepositoryProvider<ApiService>(create: (_) => api),
        RepositoryProvider<MarketRepository>(
          create: (_) => MockMarketRepository(api),
        ),
        RepositoryProvider<PortfolioRepository>(
          create: (_) => MockPortfolioRepository(api),
        ),
        RepositoryProvider<TradeRepository>(
          create: (_) => MockTradeRepository(api),
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
          BlocProvider<HomeBloc>(
            create: (BuildContext context) => HomeBloc(
              portfolioRepository: context.read<PortfolioRepository>(),
              marketRepository: context.read<MarketRepository>(),
            ),
          ),
          BlocProvider<MarketsBloc>(
            create: (BuildContext context) => MarketsBloc(
              marketRepository: context.read<MarketRepository>(),
            ),
          ),
          BlocProvider<TradeBloc>(
            create: (BuildContext context) => TradeBloc(
              tradeRepository: context.read<TradeRepository>(),
            ),
          ),
          BlocProvider<PortfolioBloc>(
            create: (BuildContext context) => PortfolioBloc(
              portfolioRepository: context.read<PortfolioRepository>(),
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
