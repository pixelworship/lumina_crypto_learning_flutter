import 'dart:async';
import 'dart:collection';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/concurrency/background.dart';
import '../../../core/diagnostics/mrm_trace.dart';
import '../../../data/models/candle.dart';
import '../../../data/models/fill.dart';
import '../../../data/models/market_event.dart';
import '../../../data/models/pause_gap.dart';
import '../../../data/models/tick.dart';
import '../../../data/models/timeframe.dart';
import '../../../data/repositories/chart_events_repository.dart';
import '../../../data/repositories/fill_repository.dart';
import '../../../data/repositories/historical_tick_repository.dart';
import '../../../data/repositories/tick_repository.dart';
import '../../../data/services/candle_aggregator.dart';
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

/// Cap on events fetched per asset. Mirrors the API's default `limit`
/// and is well below its 1000 ceiling — chart marker density beyond
/// this is unreadable anyway.
const int _maxEvents = 200;

/// How often we ask the events API for newly-created rows. Each poll
/// is a delta query (`?from=<latest+1ms>`) so the payload is empty
/// when nothing has changed; safe to run aggressively.
const Duration _defaultEventPollInterval = Duration(seconds: 1);

class ChartBloc extends Bloc<ChartEvent, ChartState> {
  ChartBloc({
    required TickRepository repository,
    required HistoricalTickRepository historicalRepository,
    required FillRepository fillRepository,
    required ChartEventsRepository eventsRepository,
    CandleAggregator aggregator = const CandleAggregator(),
    String initialSymbol = 'BTC',
    Duration? eventPollInterval = _defaultEventPollInterval,
  }) : _repository = repository,
       _historicalRepository = historicalRepository,
       _fillRepository = fillRepository,
       _eventsRepository = eventsRepository,
       _aggregator = aggregator,
       _eventPollInterval = eventPollInterval,
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
    on<_EventsPollTicked>(_onEventsPollTicked);
    on<_FillsUpdated>(_onFillsUpdated);
  }

  final TickRepository _repository;
  final HistoricalTickRepository _historicalRepository;
  final FillRepository _fillRepository;
  final ChartEventsRepository _eventsRepository;
  final CandleAggregator _aggregator;
  final Queue<Tick> _tickHistory = Queue<Tick>();

  /// Resolved pause periods. Re-applied as `Candle.gap` slots whenever
  /// the candle list is rebuilt (timeframe change), so gaps persist
  /// visually across the session.
  final List<PauseGap> _pastGaps = <PauseGap>[];

  /// Wall-clock interval between events polls. Null disables polling
  /// entirely (used by tests so periodic timers don't outlive the
  /// test harness).
  final Duration? _eventPollInterval;

  StreamSubscription<Tick>? _subscription;
  StreamSubscription<List<Fill>>? _fillSubscription;
  Timer? _eventPollTimer;

  /// Watermark for the events delta poller. Set to the window's `to`
  /// after a successful range fetch (so the poller picks up where
  /// the window left off), then advanced to the latest event's
  /// timestamp on every poll that returns rows. Null until the
  /// initial load completes.
  DateTime? _eventCursor;

  Future<void> _onStarted(ChartStarted event, Emitter<ChartState> emit) async {
    if (state.isStreaming) return;
    final String symbol = event.symbol ?? state.symbol;
    // Sync the bloc's tracked offset with the shared feed's actual
    // value before any data is loaded. The chart bloc is route-
    // scoped but the feed is app-scoped, so a previously-dialed
    // offset survives navigation. Without this sync, `state.priceOffset`
    // would start at 0 while the feed reports a non-zero value —
    // the next user dial would then overwrite (rather than increment)
    // the feed offset, briefly spiking the chart and then collapsing
    // it as live ticks arrive at the new (lower) absolute price.
    emit(
      state.copyWith(
        isStreaming: true,
        symbol: symbol,
        priceOffset: _repository.priceOffset(symbol),
      ),
    );
    await _loadFor(symbol, emit);
  }

  Future<void> _onStopped(ChartStopped event, Emitter<ChartState> emit) async {
    await _subscription?.cancel();
    _subscription = null;
    await _fillSubscription?.cancel();
    _fillSubscription = null;
    _eventPollTimer?.cancel();
    _eventPollTimer = null;
    emit(state.copyWith(isStreaming: false));
  }

  Future<void> _onSymbolChanged(
    ChartSymbolChanged event,
    Emitter<ChartState> emit,
  ) async {
    MrmTrace.mark(
      30,
      'ChartBloc._onSymbolChanged',
      'from=${state.symbol} to=${event.symbol}',
    );
    if (event.symbol == state.symbol) {
      MrmTrace.mark(31, 'ChartBloc.symbolChanged short-circuit (same symbol)');
      return;
    }

    // Tear down the current subscription + reset internal queues so
    // ticks for the previous symbol can't bleed into the new one's
    // candle history. Fills are scoped per-symbol too — drop the
    // previous symbol's subscription before re-subscribing below.
    await _subscription?.cancel();
    _subscription = null;
    await _fillSubscription?.cancel();
    _fillSubscription = null;
    // Stop polling against the old symbol; `_loadFor` re-arms the
    // timer once the new symbol's initial events land. Drop the
    // cursor too — the new symbol gets a fresh one in `_loadFor`.
    _eventPollTimer?.cancel();
    _eventPollTimer = null;
    _eventCursor = null;
    _tickHistory.clear();
    _pastGaps.clear();

    // Step 1: clear the previous asset's chart immediately and surface
    // a loading state. Setting `candles: []` causes the chart widget
    // to render a full-screen loading indicator until step 2 fills
    // in cached data (if any). Re-sync `priceOffset` to whatever the
    // shared feed reports for the new symbol — different assets can
    // hold independent debug offsets, so carrying the previous
    // symbol's value would desync the bloc from the feed.
    emit(
      state.copyWith(
        symbol: event.symbol,
        candles: const <Candle>[],
        events: const <MarketEvent>[],
        fills: const <Fill>[],
        clearLastPrice: true,
        clearPauseStartedAt: true,
        isPaused: false,
        isLoadingHistory: true,
        priceOffset: _repository.priceOffset(event.symbol),
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
      MrmTrace.mark(
        33,
        'ChartBloc cache-hit rebuild start',
        'ticks=${_tickHistory.length}',
      );
      final List<Candle> rebuiltCached = await _rebuildOffMain(
        ticks: _tickHistory.toList(growable: false),
        timeframe: state.timeframe,
      );
      MrmTrace.mark(
        34,
        'ChartBloc cache-hit rebuild done',
        'candles=${rebuiltCached.length}',
      );
      // Guard against the user switching assets again mid-rebuild —
      // bloc events serialize so this is rare, but the explicit
      // check keeps stale candles from leaking into the new symbol.
      if (state.symbol != event.symbol) return;
      emit(
        state.copyWith(candles: rebuiltCached, lastPrice: cached.last.price),
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
  /// [_historyPageWindow] of ticks, rebuilds candles, fetches the
  /// matching events window from the API, and (re-)subscribes to the
  /// live tick stream for [symbol]. Older windows are loaded on
  /// demand via `HistoryExtendRequested` (paginated, cache-friendly).
  ///
  /// Toggles [ChartState.isLoadingHistory] across the await so the
  /// chart UI can render a small "loading more" overlay even when
  /// the cache already provided initial candles.
  Future<void> _loadFor(String symbol, Emitter<ChartState> emit) async {
    MrmTrace.mark(36, 'ChartBloc._loadFor start', 'symbol=$symbol');
    emit(state.copyWith(isLoadingHistory: true));

    final DateTime now = DateTime.now();
    final DateTime windowStart = now.subtract(_historyPageWindow);

    // Kick the events fetch off in parallel — it's an independent
    // network call to a different service, so there's no reason it
    // should serialize behind the tick fetch + rebuild.
    final Future<List<MarketEvent>> eventsFuture = _eventsRepository
        .fetchEventsInRange(
          symbol: symbol,
          from: windowStart,
          to: now,
          limit: _maxEvents,
        );
    // Cursor for the delta poller — anything created strictly after
    // `now` was not part of this window fetch and is the poller's
    // responsibility from here on. Set it before any async gap so a
    // poll that sneaks in mid-load can still make a sensible call.
    _eventCursor = now;

    MrmTrace.mark(37, 'ChartBloc.fetchTicks await');
    final List<Tick> history = await _historicalRepository.fetchTicks(
      symbol: symbol,
      start: windowStart,
      end: now,
    );
    MrmTrace.mark(38, 'ChartBloc.fetchTicks done', 'ticks=${history.length}');
    _tickHistory
      ..clear()
      ..addAll(history);
    while (_tickHistory.length > _maxTickHistory) {
      _tickHistory.removeFirst();
    }
    MrmTrace.mark(
      39,
      'ChartBloc rebuild start',
      'ticks=${_tickHistory.length}',
    );
    final List<Candle> candles = await _rebuildOffMain(
      ticks: _tickHistory.toList(growable: false),
      timeframe: state.timeframe,
    );
    MrmTrace.mark(40, 'ChartBloc rebuild done', 'candles=${candles.length}');
    if (state.symbol != symbol) return;

    final List<MarketEvent> events = await eventsFuture;
    if (state.symbol != symbol) return;

    emit(
      state.copyWith(
        candles: candles,
        events: events,
        lastPrice: history.isNotEmpty ? history.last.price : null,
        isLoadingHistory: false,
      ),
    );
    MrmTrace.mark(41, 'ChartBloc emit success');

    await _subscription?.cancel();
    _subscription = _repository
        .watchTicks(symbol)
        .listen((Tick tick) => add(_TickReceived(tick)));
    MrmTrace.end(42, 'ChartBloc subscribed (asset-tap flow complete)');

    // Per-symbol fills stream. The repository's `watchFills` replays
    // the current snapshot synchronously to new subscribers, so a
    // pre-existing fill list lands in `state.fills` without an
    // explicit `getFills` call. Subsequent purchases broadcast fresh
    // snapshots through the same stream.
    await _fillSubscription?.cancel();
    _fillSubscription = _fillRepository
        .watchFills(symbol)
        .listen((List<Fill> fills) => add(_FillsUpdated(fills)));

    _scheduleEventPoll();
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
    final List<Candle> withGaps = await _rebuildOffMain(
      ticks: _tickHistory.toList(growable: false),
      timeframe: event.timeframe,
      gaps: _pastGaps,
    );
    emit(state.copyWith(timeframe: event.timeframe, candles: withGaps));
  }

  void _onTickSpeedChanged(TickSpeedChanged event, Emitter<ChartState> emit) {
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

    // Hand the dial to the live feed and walk away. Critically, we
    // do NOT shift `_tickHistory`, do NOT invalidate the historical
    // cache, and do NOT rebuild candles here — the past must stay
    // bit-for-bit identical to what was already on screen.
    //
    // The feed records the dial as a timestamped `OffsetEvent`. Its
    // `priceAt(t)` is then time-aware: queries for past `t` see no
    // offset (the event hadn't happened yet), and live ticks emitted
    // from this moment forward are baked at the new offset. The
    // visible chart picks the change up naturally on the next live
    // tick — `_aggregator.foldTick` opens or extends the current
    // candle at the new price, producing a clean step at the dial
    // moment while every prior candle is left untouched.
    _repository.setPriceOffset(state.symbol, clamped);
    emit(state.copyWith(priceOffset: clamped));
  }

  void _onGlowToggled(GlowToggled event, Emitter<ChartState> emit) {
    emit(state.copyWith(glowEnabled: !state.glowEnabled));
  }

  void _onAutoScaleToggled(AutoScaleToggled event, Emitter<ChartState> emit) {
    emit(state.copyWith(autoScaleEnabled: !state.autoScaleEnabled));
  }

  void _onVolumeOverlayToggled(
    VolumeOverlayToggled event,
    Emitter<ChartState> emit,
  ) {
    emit(state.copyWith(volumeOverlayEnabled: !state.volumeOverlayEnabled));
  }

  void _onPauseToggled(PauseToggled event, Emitter<ChartState> emit) {
    final bool next = !state.isPaused;
    // Truly stop / resume tick generation. While paused, real time keeps
    // advancing on the wall clock, so resumption produces a real time
    // gap between the last pre-pause candle and the next live tick. We
    // mark that gap visually with permanent "DATA UNAVAILABLE" slots.
    _repository.setPaused(next);
    if (next) {
      emit(state.copyWith(isPaused: true, pauseStartedAt: DateTime.now()));
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
    emit(
      state.copyWith(
        isPaused: false,
        clearPauseStartedAt: true,
        candles: withGap,
      ),
    );
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

    final List<Candle> withRemainingGaps = await _rebuildOffMain(
      ticks: _tickHistory.toList(growable: false),
      timeframe: state.timeframe,
      gaps: _pastGaps,
    );

    emit(state.copyWith(candles: withRemainingGaps, isBackfilling: false));
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

    final List<Candle> withGaps = await _rebuildOffMain(
      ticks: _tickHistory.toList(growable: false),
      timeframe: state.timeframe,
      gaps: _pastGaps,
    );

    // Refetch events spanning the new (wider) window so markers
    // populate the freshly-revealed history. The API caps at 1000
    // and the chart_events table is small, so we re-pull the full
    // visible window rather than diff-merging. Reset the delta
    // cursor to the new window's end so the poller picks up from
    // there instead of double-fetching anything covered by the
    // window query.
    final DateTime windowEnd = DateTime.now();
    final List<MarketEvent> events = await _eventsRepository
        .fetchEventsInRange(
          symbol: state.symbol,
          from: _tickHistory.first.timestamp,
          to: windowEnd,
          limit: _maxEvents,
        );
    _eventCursor = windowEnd;

    emit(
      state.copyWith(
        candles: withGaps,
        events: events,
        isExtendingHistory: false,
      ),
    );
  }

  /// Forwards a fresh per-symbol fills snapshot from
  /// [FillRepository.watchFills] into [ChartState]. The repository
  /// scopes its broadcast to the symbol the bloc subscribed with, so
  /// no extra filter is needed here — but we still guard against a
  /// late event that arrives after a symbol switch by short-
  /// circuiting when [event.fills] mentions a different symbol.
  void _onFillsUpdated(_FillsUpdated event, Emitter<ChartState> emit) {
    if (event.fills.isNotEmpty &&
        event.fills.first.symbol.toUpperCase() != state.symbol.toUpperCase()) {
      return;
    }
    emit(state.copyWith(fills: event.fills));
  }

  /// Periodic delta-fetch for newly-created `chart_events` rows.
  ///
  /// Hits `GET /v1/events/since?since=<cursor>`, which uses strict
  /// greater-than semantics on the server — so the cursor is just
  /// "the timestamp of the latest event we've ever seen" and never
  /// needs an off-by-one fudge. Cursor is initialized in `_loadFor`
  /// to the window-fetch's `to` and advanced here to the newest
  /// event's timestamp on every successful poll, so the same row is
  /// never re-fetched.
  ///
  /// (Deletions in the upstream table aren't visible through this
  /// channel — a server-pushed feed would be needed for that. Not a
  /// concern today since the dashboard is the only writer and edits
  /// are append-only.)
  Future<void> _onEventsPollTicked(
    _EventsPollTicked event,
    Emitter<ChartState> emit,
  ) async {
    // The bloc's event queue serializes handlers, so a poll can't
    // overlap with `_loadFor` itself — but the timer might fire
    // mid-load and queue this handler behind it. By the time we run
    // the symbol may have changed (or the user may have stopped
    // streaming); short-circuit without re-arming so we don't tail
    // a torn-down session.
    if (!state.isStreaming) return;
    final DateTime? cursor = _eventCursor;
    if (cursor == null) {
      // Initial load hasn't completed yet — try again next tick.
      _scheduleEventPoll();
      return;
    }
    final String symbol = state.symbol;

    final List<MarketEvent> incoming = await _eventsRepository
        .fetchEventsSince(
          symbol: symbol,
          since: cursor,
        );
    // Symbol could have switched out from under us while the await
    // was in flight; the new symbol's _loadFor will re-arm the timer
    // with its own cursor.
    if (state.symbol != symbol) return;

    if (incoming.isNotEmpty) {
      final List<MarketEvent> merged = _mergeEvents(state.events, incoming);
      // Always advance the cursor — even if the merged list length
      // didn't change (e.g. a duplicate id slipped through), the
      // server has confirmed there's nothing older worth re-fetching.
      _eventCursor = incoming.last.timestamp;
      if (merged.length != state.events.length) {
        emit(state.copyWith(events: merged));
      }
    }

    _scheduleEventPoll();
  }

  /// Returns a new sorted-ascending list combining [existing] with any
  /// rows in [incoming] whose ids aren't already present. Trims to
  /// [_maxEvents] from the front (oldest) so a long-running session
  /// doesn't accumulate forever.
  List<MarketEvent> _mergeEvents(
    List<MarketEvent> existing,
    List<MarketEvent> incoming,
  ) {
    final Set<String> seen = <String>{
      for (final MarketEvent e in existing) e.id,
    };
    final List<MarketEvent> additions = <MarketEvent>[];
    for (final MarketEvent e in incoming) {
      if (seen.add(e.id)) additions.add(e);
    }
    if (additions.isEmpty) return existing;

    final List<MarketEvent> next = <MarketEvent>[...existing, ...additions]
      ..sort(
        (MarketEvent a, MarketEvent b) => a.timestamp.compareTo(b.timestamp),
      );
    while (next.length > _maxEvents) {
      next.removeAt(0);
    }
    return next;
  }

  /// Schedules the next poll exactly [_eventPollInterval] from now.
  /// Re-armed after each fire (rather than `Timer.periodic`) so timer
  /// drift can't cause pile-ups while the app is backgrounded.
  /// No-ops when polling is disabled (`_eventPollInterval == null`).
  void _scheduleEventPoll() {
    final Duration? interval = _eventPollInterval;
    if (interval == null) return;
    _eventPollTimer?.cancel();
    _eventPollTimer = Timer(interval, () {
      // Guard the inherently racy "timer fired during close()" case:
      // [Timer.cancel] doesn't yank a callback that's already crossed
      // into the event-loop queue, so without this check we'd hit
      // `StateError: Cannot add new events after calling close` when
      // a user navigates away from the asset detail screen between
      // when the timer fires and when our handler runs.
      if (isClosed) return;
      add(const _EventsPollTicked());
    });
  }

  /// Wraps [rebuildCandlesWorker] with the bloc's threshold policy.
  /// Small inputs run inline (isolate spin-up would dominate); large
  /// ones dispatch to a background isolate so the UI thread stays
  /// free to pump animations and gestures while the rebuild runs.
  ///
  /// When [gaps] is non-empty (timeframe change with active pause
  /// history; history extension) the gap splice is folded into the
  /// same isolate hop — previously the bloc rebuilt off-main and
  /// then ran [CandleAggregator.mergeGaps] back on the main thread,
  /// doubling the per-frame cost on long sessions.
  Future<List<Candle>> _rebuildOffMain({
    required List<Tick> ticks,
    required Timeframe timeframe,
    List<PauseGap> gaps = const <PauseGap>[],
  }) {
    if (ticks.length < _rebuildIsolateThreshold) {
      final List<Candle> rebuilt = _aggregator.rebuild(ticks, timeframe);
      final List<Candle> withGaps = gaps.isEmpty
          ? rebuilt
          : _aggregator.mergeGaps(rebuilt, gaps, timeframe);
      return Future<List<Candle>>.value(withGaps);
    }
    return runOffMain<RebuildArgs, List<Candle>>(
      rebuildCandlesWorker,
      (ticks: ticks, timeframe: timeframe, gaps: gaps),
      heuristicSize: ticks.length,
      threshold: _rebuildIsolateThreshold,
      debugLabel: 'candle-rebuild-${state.symbol}',
    );
  }

  @override
  Future<void> close() async {
    // Cancel the timer FIRST (synchronously) so any pending tick
    // gets pulled before we yield the event loop on the awaits
    // below. The timer's callback also re-checks `isClosed` for
    // the case where it fired but hadn't run its body yet.
    _eventPollTimer?.cancel();
    await _subscription?.cancel();
    await _fillSubscription?.cancel();
    // The tick + historical + fill repositories are owned by the
    // app's RepositoryProviders, not by this bloc. We're route-scoped
    // now — disposing them here would tear down the shared price
    // feed (and the persisted-fills cache) for every other screen.
    return super.close();
  }
}

/// Internal: the events poll timer ticked. Triggers a delta-fetch
/// against the events API for any newly-created rows.
class _EventsPollTicked extends ChartEvent {
  const _EventsPollTicked();
}

/// Internal: a tick arrived from the live stream.
class _TickReceived extends ChartEvent {
  const _TickReceived(this.tick);

  final Tick tick;

  @override
  List<Object?> get props => <Object?>[tick];
}

/// Internal: the per-symbol fills stream emitted a new snapshot.
class _FillsUpdated extends ChartEvent {
  const _FillsUpdated(this.fills);

  final List<Fill> fills;

  @override
  List<Object?> get props => <Object?>[fills];
}
