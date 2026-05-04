/// Candle aggregation buckets.
///
/// Each timeframe both sets the duration of one candle and provides a label
/// suitable for selectors and axes.
enum Timeframe {
  s1(Duration(seconds: 1), '1s'),
  s10(Duration(seconds: 10), '10s'),
  s30(Duration(seconds: 30), '30s'),
  m1(Duration(minutes: 1), '1m'),
  m5(Duration(minutes: 5), '5m'),
  m10(Duration(minutes: 10), '10m'),
  m15(Duration(minutes: 15), '15m'),
  m30(Duration(minutes: 30), '30m'),
  h1(Duration(hours: 1), '1h');

  const Timeframe(this.duration, this.label);

  final Duration duration;
  final String label;
}
