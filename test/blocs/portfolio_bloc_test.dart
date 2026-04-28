import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_demo/data/repositories/portfolio_repository.dart';
import 'package:flutter_demo/presentation/blocs/portfolio/portfolio_bloc.dart';
import 'package:flutter_demo/presentation/blocs/portfolio/portfolio_event.dart';
import 'package:flutter_demo/presentation/blocs/portfolio/portfolio_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../fixtures/test_assets.dart';

class _MockPortfolioRepository extends Mock implements PortfolioRepository {}

void main() {
  late _MockPortfolioRepository repository;

  setUp(() {
    repository = _MockPortfolioRepository();
  });

  PortfolioBloc buildBloc() => PortfolioBloc(portfolioRepository: repository);

  group('PortfolioBloc.PortfolioRequested', () {
    blocTest<PortfolioBloc, PortfolioState>(
      'emits loading then success with the summary on happy path',
      setUp: () {
        when(
          repository.getPortfolio,
        ).thenAnswer((_) async => TestAssets.portfolio);
      },
      build: buildBloc,
      act: (PortfolioBloc bloc) => bloc.add(const PortfolioRequested()),
      expect: () => <Matcher>[
        predicate<PortfolioState>(
          (PortfolioState s) => s.status == PortfolioStatus.loading,
        ),
        predicate<PortfolioState>(
          (PortfolioState s) =>
              s.status == PortfolioStatus.success &&
              s.summary == TestAssets.portfolio,
        ),
      ],
      verify: (_) {
        verify(repository.getPortfolio).called(1);
      },
    );

    blocTest<PortfolioBloc, PortfolioState>(
      'emits loading then failure when repository throws',
      setUp: () {
        when(repository.getPortfolio).thenThrow(Exception('boom'));
      },
      build: buildBloc,
      act: (PortfolioBloc bloc) => bloc.add(const PortfolioRequested()),
      expect: () => <Matcher>[
        predicate<PortfolioState>(
          (PortfolioState s) => s.status == PortfolioStatus.loading,
        ),
        predicate<PortfolioState>(
          (PortfolioState s) =>
              s.status == PortfolioStatus.failure && s.errorMessage != null,
        ),
      ],
    );

    blocTest<PortfolioBloc, PortfolioState>(
      'clears any prior error when starting a new request',
      setUp: () {
        when(
          repository.getPortfolio,
        ).thenAnswer((_) async => TestAssets.portfolio);
      },
      build: buildBloc,
      seed: () => const PortfolioState(
        status: PortfolioStatus.failure,
        errorMessage: 'previous error',
      ),
      act: (PortfolioBloc bloc) => bloc.add(const PortfolioRequested()),
      expect: () => <Matcher>[
        predicate<PortfolioState>(
          (PortfolioState s) =>
              s.status == PortfolioStatus.loading && s.errorMessage == null,
        ),
        predicate<PortfolioState>(
          (PortfolioState s) =>
              s.status == PortfolioStatus.success && s.errorMessage == null,
        ),
      ],
    );
  });

  group('PortfolioBloc.PortfolioRefreshed', () {
    blocTest<PortfolioBloc, PortfolioState>(
      'updates the summary without re-emitting a loading state',
      setUp: () {
        when(
          repository.getPortfolio,
        ).thenAnswer((_) async => TestAssets.portfolio);
      },
      build: buildBloc,
      seed: () => const PortfolioState(status: PortfolioStatus.success),
      act: (PortfolioBloc bloc) => bloc.add(const PortfolioRefreshed()),
      expect: () => <Matcher>[
        predicate<PortfolioState>(
          (PortfolioState s) =>
              s.status == PortfolioStatus.success &&
              s.summary == TestAssets.portfolio,
        ),
      ],
    );
  });

  group('PortfolioBloc initial state', () {
    test('starts in PortfolioStatus.initial with no summary', () {
      final PortfolioBloc bloc = buildBloc();
      expect(bloc.state.status, PortfolioStatus.initial);
      expect(bloc.state.summary, isNull);
      expect(bloc.state.errorMessage, isNull);
      bloc.close();
    });
  });
}
