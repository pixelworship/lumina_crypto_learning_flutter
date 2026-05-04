import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/concurrency/background.dart';
import '../../../core/diagnostics/mrm_trace.dart';
import '../../../data/models/candle.dart';
import '../../../data/models/market_event.dart';
import '../../../data/models/pause_gap.dart';
import '../../../data/models/tick.dart';
import '../../../data/models/timeframe.dart';
import '../../../data/repositories/historical_tick_repository.dart';
import '../../../data/repositories/tick_repository.dart';
import '../../../data/services/candle_aggregator.dart';
import '../../../data/services/market_event_catalog.dart';
import 'chart_event.dart';
import 'chart_state.dart';

/// Tick-count threshold above which candle rebuilds dispatch to a
/// background isolate. Below this, the inline cost is smaller than
/// the isolate-spawn overhead. Tuned empirically — a typical 1m
/// timeframe at 24h yields ~30k ticks (well above this floor); a
/// fresh symbol switch with no cached history is well below it.
const int _rebuildIsolateThreshold = 2000;

/// Maximum number of raw ticks the bloc keeps in its working set.
/// Acts as a backstop in case a user pages back many windows in a
/// single session — the cache layer is the primary memory bound;
/// this just prevents the in-bloc deque from getting absurd.
const int _maxTickHistory = 200000;

/// Initial historical window fetched on chart load + each subsequent
/// page of "extend history". Picked to match the
/// [HistoricalTickCache] retention granularity (a multiple of one
/// page comfortably fits in a single per-symbol cache slot).
const Duration _historyPageWindow = Duration(hours: 24);

/// Bounds for the debug tick-speed multiplier.
const double _minTickSpeed = 0.125;
const double _maxTickSpeed = 32.0;

/// Bounds for the debug price offset.
const double _minPriceOffset = -1000.0;
const double _maxPriceOffset = 1000.0;

/// Period between auto-spawned market events. Strictly every five minutes
/// — no jitter — so users always know when to expect the next marker.
const Duration _eventTickInterval = Duration(minutes: 5);

/// Cap on retained events. Old entries are trimmed off the front so the
/// list doesn't grow unbounded over a long session.
const int _maxEvents = 200;

class ChartBloc extends Bloc<ChartEvent, ChartState> {
  ChartBloc({
    required TickRepository repository,
    required HistoricalTickRepository historicalRepository,
    CandleAggregator aggregator = const CandleAggregator(),
    Random? random,
    String initialSymbol = 'BTC',
  }) : _repository = repository,
       _historicalRepository = historicalRepository,
       _aggregator = aggregator,
       _random = random ?? Random(),
       super(ChartState.initial(symbol: initialSymbol)) {
    on<ChartStarted>(_onStarted);
    on<ChartStopped>(_onStopped);
    on<ChartSymbolChanged>(_onSymbolChanged);
    on<_TickReceived>(_onTickReceived);
    on<TimeframeChanged>(_onTimeframeChanged);
    on<TickSpeedChanged>(_onTickSpeedChanged);
    on<PriceOffsetChanged>(_onPriceOffsetChanged);
    on<GlowToggled>(_onGlowToggled);
    on<AutoScaleToggled>(_onAutoScaleToggled);
    on<VolumeOverlayToggled>(_onVolumeOverlayToggled);
    on<PauseToggled>(_onPauseToggled);
    on<BackfillRequested>(_onBackfillRequested);
    on<HistoryExtendRequested>(_onHistoryExtendRequested);
    on<MarketEventSpawnRequested>(_onMarketEventSpawnRequested);
    on<_MarketEventTimerTicked>(_onMarketEventTimerTicked);
  }

  final TickRepository _repository;
  final HistoricalTickRepository _historicalRepository;
  final CandleAggregator _aggregator;
  final Random _random;
  final Queue<Tick> _tickHistory = Queue<Tick>();

  /// Resolved pause periods. Re-applied as `Candle.gap` slots whenever
  /// the candle list is rebuilt (timeframe change), so gaps persist
  /// visually across the session.
  final List<PauseGap> _pastGaps = <PauseGap>[];

  StreamSubscription<Tick>? _subscription;
  Timer? _eventTimer;

  Future<void> _onStarted(
    ChartStarted event,
    Emitter<ChartState> emit,
  ) async {
    if (state.isStreaming) return;
    final String symbol = event.symbol ?? state.symbol;
    emit(state.copyWith(isStreaming: true, symbol: symbol));
    await _loadFor(symbol, emit);
  }

  Future<void> _onStopped(
    ChartStopped event,
    Emitter<ChartState> emit,
  ) async {
    await _subscription?.cancel();
    _subscription = null;
    _eventTimer?.cancel();
    _eventTimer = null;
    emit(state.copyWith(isStreaming: false));
  }

  Future<void> _onSymbolChanged(
    ChartSymbolChanged event,
    Emitter<ChartState> emit,
  ) async {
    MrmTrace.mark(30, 'ChartBloc._onSymbolChanged',
        'from=${state.symbol} to=${event.symbol}');
    if (event.symbol == state.symbol) {
      MrmTrace.mark(31, 'ChartBloc.symbolChanged short-circuit (same symbol)');
      return;
    }

    // Tear down the current subscription + reset internal queues so
    // ticks for the previous symbol can't bleed into the new one's
    // candle history.
    await _subscription?.cancel();
    _subscription = null;
    _tickHistory.clear();
    _pastGaps.clear();

    // Step 1: clear the previous asset's chart immediately and surface
    // a loading state. Setting `candles: []` causes the chart widget
    // to render a full-screen loading indicator until step 2 fills
    // in cached data (if any).
    emit(
      state.copyWith(
        symbol: event.symbol,
        candles: const <Candle>[],
        events: const <MarketEvent>[],
        clearLastPrice: true,
        clearPauseStartedAt: true,
        isPaused: false,
        isLoadingHistory: true,
      ),
    );
    MrmTrace.mark(31, 'ChartBloc emit clear');

    // Step 2: synchronously check the historical cache. On a cache
    // hit we render the cached candles right away so the user sees
    // *something* for the new asset (with the loading overlay still
    // visible because we may yet fetch more recent slices); on a
    // miss we stay in the empty/loading state until step 3 lands.
    final DateTime now = DateTime.now();
    final List<Tick> cached = _historicalRepository.peekTicks(
      symbol: event.symbol,
      start: now.subtract(_historyPageWindow),
      end: now,
    );
    MrmTrace.mark(32, 'ChartBloc cache peek done', 'cached=${cached.length}');
    if (cached.isNotEmpty) {
      _tickHistory.addAll(cached);
      MrmTrace.mark(33, 'ChartBloc cache-hit rebuild start',
          'ticks=${_tickHistory.length}');
      final List<Candle> rebuiltCached = await _rebuildOffMain(
        ticks: _tickHistory.toList(growable: false),
        timeframe: state.timeframe,
      );
      MrmTrace.mark(34, 'ChartBloc cache-hit rebuild done',
          'candles=${rebuiltCached.length}');
      // Guard against the user switching assets again mid-rebuild —
      // bloc events serialize so this is rare, but the explicit
      // check keeps stale candles from leaking into the new symbol.
      if (state.symbol != event.symbol) return;
      emit(
        state.copyWith(
          candles: rebuiltCached,
          lastPrice: cached.last.price,
        ),
      );
      MrmTrace.mark(35, 'ChartBloc cache-hit emit');
    }

    // Step 3: full async load (cache + any missing pages from the
    // historical API) and re-subscribe to live ticks.
    if (state.isStreaming) {
      await _loadFor(event.symbol, emit);
    } else {
      emit(state.copyWith(isLoadingHistory: false));
      MrmTrace.mark(40, 'ChartBloc.symbolChanged done (not streaming)');
    }
  }

  /// Shared loading path for both `ChartStarted` and
  /// `ChartSymbolChanged`: fetches the most recent
  /// [_historyPageWindow] of history, rebuilds candles, seeds market
  /// events, and (re-)subscribes to the live tick stream for
  /// [symbol]. Older windows are loaded on demand via
  /// `HistoryExtendRequested` (paginated, cache-friendly).
  ///
  /// Toggles [ChartState.isLoadingHistory] across the await so the
  /// chart UI can render a small "loading more" overlay even when
  /// the cache already provided initial candles.
  Future<void> _loadFor(String symbol, Emitter<ChartState> emit) async {
    MrmTrace.mark(36, 'ChartBloc._loadFor start', 'symbol=$symbol');
    emit(state.copyWith(isLoadingHistory: true));

    final DateTime now = DateTime.now();
    MrmTrace.mark(37, 'ChartBloc.fetchTicks await');
    final List<Tick> history = await _historicalRepository.fetchTicks(
      symbol: symbol,
      start: now.subtract(_historyPageWindow),
      end: now,
    );
    MrmTrace.mark(38, 'ChartBloc.fetchTicks done', 'ticks=${history.length}');
    _tickHistory
      ..clear()
      ..addAll(history);
    while (_tickHistory.length > _maxTickHistory) {
      _tickHistory.removeFirst();
    }
    MrmTrace.mark(39, 'ChartBloc rebuild start', 'ticks=${_tickHistory.length}');
    final List<Candle> candles = await _rebuildOffMain(
      ticks: _tickHistory.toList(growable: false),
      timeframe: state.timeframe,
    );
    MrmTrace.mark(40, 'ChartBloc rebuild done', 'candles=${candles.length}');
    if (state.symbol != symbol) return;
    final List<MarketEvent> seededEvents = _seedHistoricalEvents(history);
    emit(
      state.copyWith(
        candles: candles,
        events: seededEvents,
        lastPrice: history.isNotEmpty ? history.last.price : null,
        isLoadingHistory: false,
      ),
    );
    MrmTrace.mark(41, 'ChartBloc emit success');

    await _subscription?.cancel();
    _subscription = _repository.watchTicks(symbol).listen(
      (Tick tick) => add(_TickReceived(tick)),
    );
    MrmTrace.end(42, 'ChartBloc subscribed (asset-tap flow complete)');

    _scheduleNextEventTick();
  }

  void _onTickReceived(_TickReceived event, Emitter<ChartState> emit) {
    _tickHistory.addLast(event.tick);
    while (_tickHistory.length > _maxTickHistory) {
      _tickHistory.removeFirst();
    }

    final List<Candle> candles = List<Candle>.from(state.candles);
    final Candle? current = candles.isNotEmpty ? candles.last : null;
    final Candle next = _aggregator.foldTick(
      current: current,
      tick: event.tick,
      tf: state.timeframe,
    );
    if (current == null || next.timestamp.isAfter(current.timestamp)) {
      candles.add(next);
    } else {
      candles[candles.length - 1] = next;
    }

    emit(state.copyWith(candles: candles, lastPrice: event.tick.price));
  }

  Future<void> _onTimeframeChanged(
    TimeframeChanged event,
    Emitter<ChartState> emit,
  ) async {
    if (event.timeframe == state.timeframe) return;
    final List<Candle> rebuilt = await _rebuildOffMain(
      ticks: _tickHistory.toList(growable: false),
      timeframe: event.timeframe,
    );
    final List<Candle> withGaps =
        _aggregator.mergeGaps(rebuilt, _pastGaps, event.timeframe);
    emit(state.copyWith(timeframe: event.timeframe, candles: withGaps));
  }

  void _onTickSpeedChanged(
    TickSpeedChanged event,
    Emitter<ChartState> emit,
  ) {
    final double clamped = event.multiplier.clamp(_minTickSpeed, _maxTickSpeed);
    if (clamped == state.tickSpeed) return;
    _repository.setSpeedMultiplier(clamped);
    emit(state.copyWith(tickSpeed: clamped));
  }

  Future<void> _onPriceOffsetChanged(
    PriceOffsetChanged event,
    Emitter<ChartState> emit,
  ) async {
    final double clamped = event.offset.clamp(_minPriceOffset, _maxPriceOffset);
    if (clamped == state.priceOffset) return;

    final double delta = clamped - state.priceOffset;

    // (1) Push the new offset into the live feed so live ticks +
    //     synchronous `currentPrice` reads pick it up immediately
    //     (the feed broadcasts a fresh price update internally).
    _repository.setPriceOffset(state.symbol, clamped);

    // (2) Invalidate the historical cache for this symbol so the
    //     next `fetchTicks` returns freshly-synthesized data with
    //     the new offset baked in — instead of serving stale
    //     pre-offset ticks the next time the user revisits.
    _historicalRepository.invalidate(state.symbol);

    // (3) Shift every tick already in the bloc's working set by the
    //     delta. This is mathematically identical to refetching the
    //     whole window with the new offset (`oldTickPrice + delta
    //     == noise(t) + newOffset`) but instant and zero-cost — so
    //     the entire visible chart shifts on the next frame,
    //     matching the new live price.
    if (delta != 0 && _tickHistory.isNotEmpty) {
      final List<Tick> shifted = _tickHistory
          .map(
            (Tick t) => Tick(
              price: t.price + delta,
              side: t.side,
              volume: t.volume,
              timestamp: t.timestamp,
            ),
          )
          .toList(growable: false);
      _tickHistory
        ..clear()
        ..addAll(shifted);
    }

    final List<Candle> rebuilt = await _rebuildOffMain(
      ticks: _tickHistory.toList(growable: false),
      timeframe: state.timeframe,
    );
    final List<Candle> withGaps =
        _aggregator.mergeGaps(rebuilt, _pastGaps, state.timeframe);

    emit(
      state.copyWith(
        priceOffset: clamped,
        candles: withGaps,
        lastPrice:
            _tickHistory.isNotEmpty ? _tickHistory.last.price : null,
      ),
    );
  }

  void _onGlowToggled(GlowToggled event, Emitter<ChartState> emit) {
    emit(state.copyWith(glowEnabled: !state.glowEnabled));
  }

  void _onAutoScaleToggled(
    AutoScaleToggled event,
    Emitter<ChartState> emit,
  ) {
    emit(state.copyWith(autoScaleEnabled: !state.autoScaleEnabled));
  }

  void _onVolumeOverlayToggled(
    VolumeOverlayToggled event,
    Emitter<ChartState> emit,
  ) {
    emit(state.copyWith(
      volumeOverlayEnabled: !state.volumeOverlayEnabled,
    ));
  }

  void _onPauseToggled(PauseToggled event, Emitter<ChartState> emit) {
    final bool next = !state.isPaused;
    // Truly stop / resume tick generation. While paused, real time keeps
    // advancing on the wall clock, so resumption produces a real time
    // gap between the last pre-pause candle and the next live tick. We
    // mark that gap visually with permanent "DATA UNAVAILABLE" slots.
    _repository.setPaused(next);
    if (next) {
      emit(state.copyWith(
        isPaused: true,
        pauseStartedAt: DateTime.now(),
      ));
      return;
    }

    final DateTime? pauseStarted = state.pauseStartedAt;
    if (pauseStarted == null) {
      emit(state.copyWith(isPaused: false, clearPauseStartedAt: true));
      return;
    }
    final PauseGap gap = PauseGap(start: pauseStarted, end: DateTime.now());
    _pastGaps.add(gap);
    final List<Candle> withGap = _aggregator.mergeGaps(
      state.candles,
      <PauseGap>[gap],
      state.timeframe,
    );
    emit(state.copyWith(
      isPaused: false,
      clearPauseStartedAt: true,
      candles: withGap,
    ));
  }

  Future<void> _onBackfillRequested(
    BackfillRequested event,
    Emitter<ChartState> emit,
  ) async {
    if (state.isBackfilling) return;
    if (_pastGaps.isEmpty) return;

    emit(state.copyWith(isBackfilling: true));

    // Snapshot gaps so concurrent pauses during the await don't get
    // lost — anything not in this list stays in `_pastGaps`.
    final List<PauseGap> gapsToFill = List<PauseGap>.from(_pastGaps);
    final List<Tick> fetched = <Tick>[];
    for (final PauseGap gap in gapsToFill) {
      final List<Tick> ticks = await _historicalRepository.fetchTicks(
        symbol: state.symbol,
        start: gap.start,
        end: gap.end,
      );
      fetched.addAll(ticks);
    }

    if (fetched.isNotEmpty) {
      final List<Tick> merged = <Tick>[..._tickHistory, ...fetched]
        ..sort((Tick a, Tick b) => a.timestamp.compareTo(b.timestamp));
      _tickHistory
        ..clear()
        ..addAll(merged);
      while (_tickHistory.length > _maxTickHistory) {
        _tickHistory.removeFirst();
      }
    }

    _pastGaps.removeWhere(gapsToFill.contains);

    final List<Candle> rebuilt = await _rebuildOffMain(
      ticks: _tickHistory.toList(growable: false),
      timeframe: state.timeframe,
    );
    final List<Candle> withRemainingGaps =
        _aggregator.mergeGaps(rebuilt, _pastGaps, state.timeframe);

    emit(state.copyWith(
      candles: withRemainingGaps,
      isBackfilling: false,
    ));
  }

  Future<void> _onHistoryExtendRequested(
    HistoryExtendRequested event,
    Emitter<ChartState> emit,
  ) async {
    if (state.isExtendingHistory) return;
    if (_tickHistory.isEmpty) return;

    // Paginated history: each press fetches one [_historyPageWindow]
    // of older ticks back from whatever's currently the earliest
    // tick. Steady linear growth (24h → 48h → 72h → ...) keeps each
    // page's payload bounded and cache-friendly — far better than
    // the prior "double the entire span" approach which would ask
    // for years of data on the third press.
    final DateTime earliest = _tickHistory.first.timestamp;
    final DateTime end = earliest;
    final DateTime start = earliest.subtract(_historyPageWindow);

    emit(state.copyWith(isExtendingHistory: true));

    final List<Tick> older = await _historicalRepository.fetchTicks(
      symbol: state.symbol,
      start: start,
      end: end,
    );

    if (older.isEmpty) {
      emit(state.copyWith(isExtendingHistory: false));
      return;
    }

    // Repository returns ticks sorted ascending; prepend them in
    // that order to keep _tickHistory sorted.
    final List<Tick> merged = <Tick>[...older, ..._tickHistory];
    _tickHistory
      ..clear()
      ..addAll(merged);
    while (_tickHistory.length > _maxTickHistory) {
      _tickHistory.removeFirst();
    }

    final List<Candle> rebuilt = await _rebuildOffMain(
      ticks: _tickHistory.toList(growable: false),
      timeframe: state.timeframe,
    );
    final List<Candle> withGaps =
        _aggregator.mergeGaps(rebuilt, _pastGaps, state.timeframe);

    emit(state.copyWith(
      candles: withGaps,
      isExtendingHistory: false,
    ));
  }

  void _onMarketEventSpawnRequested(
    MarketEventSpawnRequested event,
    Emitter<ChartState> emit,
  ) {
    emit(state.copyWith(events: _appendEvent(state.events, DateTime.now())));
  }

  void _onMarketEventTimerTicked(
    _MarketEventTimerTicked event,
    Emitter<ChartState> emit,
  ) {
    if (!state.isStreaming) return;
    emit(state.copyWith(events: _appendEvent(state.events, DateTime.now())));
    _scheduleNextEventTick();
  }

  /// Appends a freshly-rolled mock event to [existing], trimming oldest
  /// entries past [_maxEvents]. Returns a new list.
  List<MarketEvent> _appendEvent(
    List<MarketEvent> existing,
    DateTime timestamp,
  ) {
    final List<MarketEvent> next = List<MarketEvent>.from(existing)
      ..add(randomMarketEvent(timestamp: timestamp, random: _random));
    while (next.length > _maxEvents) {
      next.removeAt(0);
    }
    return next;
  }

  /// Wraps [rebuildCandlesWorker] with the bloc's threshold policy.
  /// Small inputs run inline (isolate spin-up would dominate); large
  /// ones dispatch to a background isolate so the UI thread stays
  /// free to pump animations and gestures while the rebuild runs.
  Future<List<Candle>> _rebuildOffMain({
    required List<Tick> ticks,
    required Timeframe timeframe,
  }) {
    if (ticks.length < _rebuildIsolateThreshold) {
      return Future<List<Candle>>.value(_aggregator.rebuild(ticks, timeframe));
    }
    return runOffMain<RebuildArgs, List<Candle>>(
      rebuildCandlesWorker,
      (ticks: ticks, timeframe: timeframe),
      heuristicSize: ticks.length,
      threshold: _rebuildIsolateThreshold,
      debugLabel: 'candle-rebuild-${state.symbol}',
    );
  }

  /// Sprinkles a handful of events across the historical window so the
  /// chart isn't empty of markers on first load.
  List<MarketEvent> _seedHistoricalEvents(List<Tick> history) {
    if (history.length < 2) return const <MarketEvent>[];
    final DateTime start = history.first.timestamp;
    final DateTime end = history.last.timestamp;
    final int spanMs = end.difference(start).inMilliseconds;
    if (spanMs <= 0) return const <MarketEvent>[];

    // ~one event per hour of recent history, capped at 24, so users see
    // a handful of markers immediately without overwhelming the timeline.
    final int desired =
        (spanMs / Duration.millisecondsPerHour).clamp(6, 24).toInt();
    final List<MarketEvent> events = <MarketEvent>[];
    for (int i = 0; i < desired; i++) {
      // Use nextDouble * spanMs instead of nextInt(spanMs) — for a
      // 1-year window spanMs exceeds Random.nextInt's 2^32 cap.
      final int offsetMs = (_random.nextDouble() * spanMs).toInt();
      final DateTime ts = start.add(Duration(milliseconds: offsetMs));
      events.add(randomMarketEvent(timestamp: ts, random: _random));
    }
    events.sort(
      (MarketEvent a, MarketEvent b) => a.timestamp.compareTo(b.timestamp),
    );
    return events;
  }

  /// Schedules the next periodic spawn exactly [_eventTickInterval] from
  /// now. Re-armed each fire (rather than a `Timer.periodic`) so timer
  /// drift can't cause pile-ups while the app is backgrounded.
  void _scheduleNextEventTick() {
    _eventTimer?.cancel();
    _eventTimer = Timer(
      _eventTickInterval,
      () => add(const _MarketEventTimerTicked()),
    );
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    _eventTimer?.cancel();
    // The tick + historical repositories are owned by the app's
    // RepositoryProviders, not by this bloc. We're route-scoped now —
    // disposing them here would tear down the shared price feed for
    // every other screen.
    return super.close();
  }
}

/// Internal: the periodic event timer ticked.
class _MarketEventTimerTicked extends ChartEvent {
  const _MarketEventTimerTicked();
}

/// Internal: a tick arrived from the live stream.
class _TickReceived extends ChartEvent {
  const _TickReceived(this.tick);

  final Tick tick;

  @override
  List<Object?> get props => <Object?>[tick];
}
