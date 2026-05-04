import 'dart:async';

import '../models/fill.dart';
import '../services/fill_storage.dart';

/// Repository abstraction over the user's fills (executed purchases).
///
/// Fills are their own data source — independent of [TickRepository]
/// and [HistoricalTickRepository] so a future real-feed migration
/// touches one boundary at a time. The chart bloc consumes fills the
/// same way it consumes [MarketEvent]s: hydrate on start/symbol
/// change, then watch a per-symbol stream for live updates.
abstract class FillRepository {
  /// One-shot read of every fill for [symbol], sorted ascending by
  /// timestamp.
  Future<List<Fill>> getFills(String symbol);

  /// Broadcast stream that emits the full per-symbol fill list every
  /// time a fill is added (or, in the future, removed). Always emits
  /// the current snapshot synchronously to new listeners so callers
  /// don't have to combine `getFills` + `watchFills` themselves.
  Stream<List<Fill>> watchFills(String symbol);

  /// Persists [fill] and broadcasts the updated per-symbol list.
  /// Idempotent on [Fill.id] — a duplicate id overwrites in place
  /// instead of producing two markers.
  Future<void> recordFill(Fill fill);

  /// Releases any held resources (broadcast controllers, etc).
  /// Production wiring calls this from the app's
  /// [RepositoryProvider.dispose]; tests call it explicitly.
  Future<void> dispose();
}

/// Concrete repository: in-memory cache + per-symbol broadcast stream
/// + Hive-backed persistence.
///
/// Architecture choice — why three layers:
///
/// 1. **Hive** owns the durability story. Every successful
///    [recordFill] hits the box before we update memory, so a crash
///    mid-call still leaves the user with the fill they (already)
///    saw acknowledged.
///
/// 2. **The in-memory cache** (`_cache`) is what the UI reads. It's
///    a per-symbol `List<Fill>` kept sorted ascending. Hydration is
///    lazy: a symbol's list materializes the first time anyone calls
///    [getFills] / [watchFills] for that symbol. Re-reads after
///    hydration are O(1).
///
/// 3. **Per-symbol broadcast controllers** decouple writers from
///    readers. The chart bloc subscribes once per symbol; every
///    [recordFill] for that symbol delivers the updated list on the
///    next microtask without the bloc needing to poll.
class LocalFillRepository implements FillRepository {
  LocalFillRepository({required FillStorage storage}) : _storage = storage;

  final FillStorage _storage;

  /// Per-symbol cache, keyed by upper-cased symbol. Created lazily on
  /// first read; subsequent reads are constant-time list snapshots.
  final Map<String, List<Fill>> _cache = <String, List<Fill>>{};

  /// Per-symbol broadcast controllers. Created lazily on first
  /// [watchFills] call. We never close them mid-app-lifetime; the
  /// repository owns them and tears them down in [dispose].
  final Map<String, StreamController<List<Fill>>> _controllers =
      <String, StreamController<List<Fill>>>{};

  bool _disposed = false;

  @override
  Future<List<Fill>> getFills(String symbol) async {
    final String key = symbol.toUpperCase();
    return _hydrate(key);
  }

  @override
  Stream<List<Fill>> watchFills(String symbol) {
    final String key = symbol.toUpperCase();
    final StreamController<List<Fill>> controller = _controllerFor(key);
    // `Stream.multi` would also work here, but a sync replay via the
    // first `Stream` event keeps callers' code as a single
    // `subscription = stream.listen(...)` instead of needing to
    // combine an initial-value future.
    return controller.stream.transform(
      _ReplayInitialTransformer<List<Fill>>(() => _hydrate(key)),
    );
  }

  @override
  Future<void> recordFill(Fill fill) async {
    if (_disposed) return;
    await _storage.put(fill);

    final String key = fill.symbol.toUpperCase();
    final List<Fill> current = await _hydrate(key);
    final List<Fill> next = <Fill>[
      for (final Fill f in current)
        if (f.id != fill.id) f,
      fill,
    ]..sort((Fill a, Fill b) => a.timestamp.compareTo(b.timestamp));
    _cache[key] = List<Fill>.unmodifiable(next);

    final StreamController<List<Fill>>? controller = _controllers[key];
    if (controller != null && !controller.isClosed) {
      controller.add(_cache[key]!);
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    for (final StreamController<List<Fill>> c in _controllers.values) {
      await c.close();
    }
    _controllers.clear();
    _cache.clear();
  }

  /// Returns the cached per-symbol list, hydrating from disk on first
  /// access. Returned lists are unmodifiable so a caller mutating the
  /// snapshot can't corrupt the cache.
  Future<List<Fill>> _hydrate(String key) async {
    final List<Fill>? hit = _cache[key];
    if (hit != null) return hit;
    final List<Fill> fromDisk = _storage.valuesFor(key);
    final List<Fill> snapshot = List<Fill>.unmodifiable(fromDisk);
    _cache[key] = snapshot;
    return snapshot;
  }

  StreamController<List<Fill>> _controllerFor(String key) {
    return _controllers.putIfAbsent(
      key,
      () => StreamController<List<Fill>>.broadcast(),
    );
  }
}

/// Volatile, no-op-on-disk variant used by widget tests.
///
/// Same broadcast / per-symbol cache semantics as
/// [LocalFillRepository], but skips Hive entirely. Production wiring
/// should never pick this up — the `LuminaApp` constructor only
/// falls back to it when no explicit repository is provided (i.e.
/// tests that don't bother to set one up).
class InMemoryFillRepository implements FillRepository {
  final Map<String, List<Fill>> _cache = <String, List<Fill>>{};
  final Map<String, StreamController<List<Fill>>> _controllers =
      <String, StreamController<List<Fill>>>{};
  bool _disposed = false;

  @override
  Future<List<Fill>> getFills(String symbol) async {
    final String key = symbol.toUpperCase();
    return List<Fill>.unmodifiable(_cache[key] ?? const <Fill>[]);
  }

  @override
  Stream<List<Fill>> watchFills(String symbol) {
    final String key = symbol.toUpperCase();
    final StreamController<List<Fill>> controller = _controllers
        .putIfAbsent(key, () => StreamController<List<Fill>>.broadcast());
    return controller.stream.transform(
      _ReplayInitialTransformer<List<Fill>>(
        () async => List<Fill>.unmodifiable(_cache[key] ?? const <Fill>[]),
      ),
    );
  }

  @override
  Future<void> recordFill(Fill fill) async {
    if (_disposed) return;
    final String key = fill.symbol.toUpperCase();
    final List<Fill> current = _cache[key] ?? const <Fill>[];
    final List<Fill> next = <Fill>[
      for (final Fill f in current)
        if (f.id != fill.id) f,
      fill,
    ]..sort((Fill a, Fill b) => a.timestamp.compareTo(b.timestamp));
    _cache[key] = List<Fill>.unmodifiable(next);

    final StreamController<List<Fill>>? controller = _controllers[key];
    if (controller != null && !controller.isClosed) {
      controller.add(_cache[key]!);
    }
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    for (final StreamController<List<Fill>> c in _controllers.values) {
      await c.close();
    }
    _controllers.clear();
    _cache.clear();
  }
}

/// Stream transformer that prepends a single initial value (resolved
/// asynchronously) to a broadcast source.
///
/// Used by [LocalFillRepository.watchFills] so a fresh subscriber
/// gets the current snapshot before any future updates — without the
/// caller having to manually combine `getFills` + `watchFills`.
class _ReplayInitialTransformer<T> extends StreamTransformerBase<T, T> {
  _ReplayInitialTransformer(this._initial);

  final Future<T> Function() _initial;

  @override
  Stream<T> bind(Stream<T> stream) {
    late StreamController<T> controller;
    StreamSubscription<T>? subscription;

    void onListen() {
      _initial().then((T value) {
        if (controller.isClosed) return;
        controller.add(value);
      });
      subscription = stream.listen(
        controller.add,
        onError: controller.addError,
        onDone: controller.close,
      );
    }

    Future<void> onCancel() async {
      await subscription?.cancel();
      subscription = null;
    }

    controller = StreamController<T>(
      onListen: onListen,
      onCancel: onCancel,
    );
    return controller.stream;
  }
}
