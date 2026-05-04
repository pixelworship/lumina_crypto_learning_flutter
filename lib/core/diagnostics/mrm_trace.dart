import 'package:flutter/foundation.dart';

/// Lightweight diagnostic timeline for the asset-tap path.
///
/// All output is prefixed with `MRM <code>` so it can be grepped /
/// filtered out of console noise. Each call also includes the
/// elapsed milliseconds since the most recent [start] so the
/// stage-to-stage delta is obvious at a glance.
///
/// Usage:
/// ```dart
/// MrmTrace.start('tap ETH');
/// MrmTrace.mark(20, 'trade._onRequested', 'symbol=ETH');
/// MrmTrace.mark(36, 'chart.loadFor.fetchTicks done', 'ticks=28412');
/// ```
///
/// Disabled in release builds (`kDebugMode` gate) so production
/// users never see the prints and the stopwatch isn't kept alive.
class MrmTrace {
  MrmTrace._();

  static final Stopwatch _sw = Stopwatch();
  static String _label = '';

  /// Resets the timeline. Call this at the very beginning of a
  /// user-initiated flow (e.g. tapping an asset row). Subsequent
  /// [mark] calls report time relative to this point.
  static void start(String label) {
    if (!kDebugMode) return;
    _sw
      ..stop()
      ..reset()
      ..start();
    _label = label;
    debugPrint('MRM 00 +0ms START [$label]');
  }

  /// Logs a timeline entry. [code] is a stable two-digit identifier
  /// for the stage so logs can be referred to by number when
  /// debugging; [stage] is a human-readable summary; [detail]
  /// is an optional context string (counts, ranges, etc.).
  static void mark(int code, String stage, [String? detail]) {
    if (!kDebugMode) return;
    if (!_sw.isRunning) return;
    final int ms = _sw.elapsedMilliseconds;
    final String num = code.toString().padLeft(2, '0');
    final String tail = detail == null ? '' : ' [$detail]';
    debugPrint('MRM $num +${ms}ms $stage$tail');
  }

  /// Convenience for logging the end of a top-level flow with the
  /// total elapsed time. Stops the stopwatch so stray late marks
  /// don't pollute the next flow.
  static void end(int code, String stage, [String? detail]) {
    if (!kDebugMode) return;
    mark(code, stage, detail);
    _sw.stop();
  }

  /// Currently active flow label. Useful for keeping logs grouped
  /// when multiple subsystems are firing concurrently.
  static String get label => _label;
}
