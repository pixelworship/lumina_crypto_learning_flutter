import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/models/asset_category.dart';
import '../../design_system/lumina_ui.dart';
import '../blocs/markets/markets_bloc.dart';
import '../blocs/markets/markets_event.dart';
import '../blocs/markets/markets_state.dart';
import '../blocs/navigation/navigation_cubit.dart';
import '../widgets/asset_market_row.dart';

class MarketsScreen extends StatefulWidget {
  const MarketsScreen({super.key});

  @override
  State<MarketsScreen> createState() => _MarketsScreenState();
}

class _MarketsScreenState extends State<MarketsScreen> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: context.read<MarketsBloc>().state.query,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        t.spacing.xl,
        t.spacing.sm,
        t.spacing.xl,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Market Discovery',
            style: t.typography.titleLg.copyWith(
              color: t.colors.contentPrimary,
            ),
          ),
          SizedBox(height: t.spacing.md),
          LuminaTextField.search(
            controller: _controller,
            hintText: 'Search tokens, pairs, or categories...',
            onChanged: (String value) =>
                context.read<MarketsBloc>().add(MarketsSearchChanged(value)),
          ),
          SizedBox(height: t.spacing.md),
          BlocBuilder<MarketsBloc, MarketsState>(
            buildWhen: (MarketsState previous, MarketsState current) =>
                previous.category != current.category,
            builder: (BuildContext context, MarketsState state) {
              return LuminaChipBar<AssetCategory>(
                options: AssetCategory.values,
                selected: state.category,
                labelOf: (AssetCategory c) => c.label,
                onSelected: (AssetCategory c) => context
                    .read<MarketsBloc>()
                    .add(MarketsCategoryChanged(c)),
              );
            },
          ),
          SizedBox(height: t.spacing.md),
          const _ColumnHeaders(),
          const Divider(height: 1),
          Expanded(
            child: BlocBuilder<MarketsBloc, MarketsState>(
              builder: (BuildContext context, MarketsState state) {
                if (state.status == MarketsStatus.loading &&
                    state.quotes.isEmpty) {
                  return const Center(child: LuminaLoadingIndicator());
                }
                if (state.status == MarketsStatus.failure &&
                    state.quotes.isEmpty) {
                  return LuminaErrorView(
                    message: state.errorMessage ?? 'Failed to load markets.',
                    onRetry: () => context
                        .read<MarketsBloc>()
                        .add(const MarketsRequested()),
                  );
                }
                final List<dynamic> visible = state.visibleQuotes;
                if (visible.isEmpty) {
                  return LuminaEmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'No matching assets',
                    message:
                        'Try a different search term or pick another category.',
                  );
                }
                return RefreshIndicator(
                  color: t.colors.accentPrimary,
                  backgroundColor: t.colors.surfaceRaised,
                  onRefresh: () async {
                    context
                        .read<MarketsBloc>()
                        .add(const MarketsRefreshed());
                    await context.read<MarketsBloc>().stream.firstWhere(
                          (MarketsState s) =>
                              s.status != MarketsStatus.loading,
                        );
                  },
                  child: ListView.separated(
                    padding: EdgeInsets.only(
                      bottom: t.spacing.xxl,
                      top: t.spacing.xxs,
                    ),
                    itemCount: visible.length,
                    separatorBuilder:
                        (BuildContext context, int index) =>
                            const Divider(height: 1),
                    itemBuilder: (BuildContext context, int index) =>
                        AssetMarketRow(
                      quote: state.visibleQuotes[index],
                      onTap: () => context
                          .read<NavigationCubit>()
                          .select(AppTab.trade),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ColumnHeaders extends StatelessWidget {
  const _ColumnHeaders();

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    final TextStyle style = t.typography.labelMd.copyWith(
      color: t.colors.contentTertiary,
    );
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: t.spacing.xs,
        vertical: t.spacing.xs + 2,
      ),
      child: Row(
        children: <Widget>[
          SizedBox(width: 24, child: Text('#', style: style)),
          SizedBox(width: t.spacing.sm),
          Expanded(child: Text('ASSET', style: style)),
          Text('PRICE', style: style),
        ],
      ),
    );
  }
}
