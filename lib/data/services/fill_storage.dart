import 'package:hive/hive.dart';

import '../models/fill.dart';

/// Thin wrapper over a Hive [Box] of [Fill]s.
///
/// Owned by the app at the [RepositoryProvider] level — the
/// [FillRepository] reads through this and never opens the box
/// itself. Keeping the Hive surface confined here means tests can
/// substitute a fake implementation without dragging Hive (or its
/// platform side-effects) into bloc-level test code.
///
/// Box layout:
///   * one box (`fills`),
///   * key = [Fill.id] (uuid-shaped string the repository mints),
///   * value = the [Fill] itself, serialized via [FillAdapter].
///
/// Querying by symbol is a linear scan over `box.values`. For our
/// scale (a typical user accumulates dozens, maybe hundreds, of
/// purchases) this is well below any threshold where a per-symbol
/// box or secondary index would pay back its complexity. If the
/// numbers ever grow, swap [valuesFor] for an index-backed lookup
/// without changing callers.
class FillStorage {
  FillStorage({required Box<Fill> box}) : _box = box;

  /// Async constructor for production wiring. Opens the standard
  /// `fills` box and resolves the storage instance bound to it.
  /// Tests should construct directly via the unnamed constructor
  /// with a pre-opened (in-memory or temp-dir) box.
  static Future<FillStorage> open({String boxName = _defaultBoxName}) async {
    final Box<Fill> box = await Hive.openBox<Fill>(boxName);
    return FillStorage(box: box);
  }

  static const String _defaultBoxName = 'fills';

  final Box<Fill> _box;

  /// Every fill currently on disk, in the box's natural insertion
  /// order. Repository hydrates per-symbol caches off this on first
  /// access for a symbol.
  List<Fill> all() => List<Fill>.unmodifiable(_box.values);

  /// All fills for [symbol], sorted ascending by timestamp.
  ///
  /// We sort here (rather than relying on insertion order) so a
  /// future bulk import of historical fills lands in the correct
  /// order even if it's appended after the user has already traded.
  List<Fill> valuesFor(String symbol) {
    final String key = symbol.toUpperCase();
    final List<Fill> matching = <Fill>[
      for (final Fill f in _box.values)
        if (f.symbol.toUpperCase() == key) f,
    ]..sort((Fill a, Fill b) => a.timestamp.compareTo(b.timestamp));
    return matching;
  }

  /// Persists [fill]. Idempotent w.r.t. [Fill.id] — calling [put]
  /// twice with the same id overwrites in place.
  Future<void> put(Fill fill) => _box.put(fill.id, fill);

  /// Drops every fill on disk. Useful in tests; not currently
  /// surfaced through the repository.
  Future<void> clear() => _box.clear();

  /// Closes the underlying box. Production code never calls this
  /// (the box stays open for the lifetime of the app); tests use it
  /// to release handles before the temp dir is removed.
  Future<void> close() => _box.close();
}
