/// Abstraction over wall-clock time.
///
/// Code that needs the current time should depend on [Clock] rather than
/// calling [DateTime.now] directly. This makes time-dependent logic
/// (timestamps, TTLs, sparklines, schedule windows) trivially testable: tests
/// inject a [FakeClock] that returns deterministic values.
///
/// In production wire up [SystemClock] via DI/RepositoryProvider; in tests
/// pass [FakeClock] with a fixed instant or one you advance manually.
abstract class Clock {
  const Clock();

  /// Returns the current instant. Implementations may return any
  /// representation of "now" — system time, a fixed test instant, etc.
  DateTime now();
}

/// Default [Clock] backed by [DateTime.now].
class SystemClock extends Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}

/// Test-only [Clock] that returns a fixed instant unless explicitly advanced.
///
/// Designed for use in unit tests:
/// ```dart
/// final clock = FakeClock(DateTime.utc(2026, 1, 1));
/// final api = MockApiService(clock: clock);
/// expect(snapshot.timestamp, clock.now());
/// clock.advance(const Duration(minutes: 5));
/// ```
class FakeClock extends Clock {
  FakeClock([DateTime? initial])
    : _now = initial ?? DateTime.utc(2026, 1, 1, 12);

  DateTime _now;

  @override
  DateTime now() => _now;

  /// Sets the clock to an absolute instant.
  void setNow(DateTime instant) {
    _now = instant;
  }

  /// Advances the clock by [delta] (negative deltas are allowed).
  void advance(Duration delta) {
    _now = _now.add(delta);
  }
}
