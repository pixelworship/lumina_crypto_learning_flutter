import 'package:flutter_demo/core/clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SystemClock', () {
    test('returns a value close to DateTime.now()', () {
      const Clock clock = SystemClock();
      final DateTime before = DateTime.now();
      final DateTime now = clock.now();
      final DateTime after = DateTime.now();

      expect(now.isBefore(before), isFalse);
      expect(now.isAfter(after), isFalse);
    });
  });

  group('FakeClock', () {
    test('defaults to a stable instant when no value is provided', () {
      final FakeClock clock = FakeClock();
      expect(clock.now(), DateTime.utc(2026, 1, 1, 12));
    });

    test('uses the provided initial instant', () {
      final DateTime instant = DateTime.utc(2030, 6, 15, 9, 30);
      final FakeClock clock = FakeClock(instant);
      expect(clock.now(), instant);
    });

    test('setNow() replaces the current instant', () {
      final FakeClock clock = FakeClock(DateTime.utc(2026));
      final DateTime newInstant = DateTime.utc(2027, 3, 10);

      clock.setNow(newInstant);

      expect(clock.now(), newInstant);
    });

    test('advance() moves the clock forward', () {
      final FakeClock clock = FakeClock(DateTime.utc(2026, 1, 1, 12));

      clock.advance(const Duration(hours: 6, minutes: 30));

      expect(clock.now(), DateTime.utc(2026, 1, 1, 18, 30));
    });

    test('advance() accepts negative durations', () {
      final FakeClock clock = FakeClock(DateTime.utc(2026, 1, 1, 12));

      clock.advance(const Duration(hours: -2));

      expect(clock.now(), DateTime.utc(2026, 1, 1, 10));
    });

    test('multiple advance() calls compound', () {
      final FakeClock clock = FakeClock(DateTime.utc(2026, 1, 1));

      clock.advance(const Duration(days: 1));
      clock.advance(const Duration(hours: 12));
      clock.advance(const Duration(minutes: 30));

      expect(clock.now(), DateTime.utc(2026, 1, 2, 12, 30));
    });

    test('now() returns the same value if the clock has not advanced', () {
      final FakeClock clock = FakeClock(DateTime.utc(2026));

      final DateTime first = clock.now();
      final DateTime second = clock.now();
      final DateTime third = clock.now();

      expect(first, second);
      expect(second, third);
    });
  });
}
