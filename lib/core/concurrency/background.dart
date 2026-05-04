import 'package:flutter/foundation.dart';

/// Runs [callback] off the main thread on native targets, returning
/// a future that completes with its result.
///
/// On native (mobile/desktop) we delegate to Flutter's [compute],
/// which spawns a short-lived isolate so the work doesn't block the
/// UI thread. Isolate spin-up has a fixed cost (~10–30 ms), so for
/// very small jobs running inline can actually be faster — callers
/// can pass [heuristicSize] together with a [threshold] to opt out
/// of the isolate dispatch when the workload is trivial.
///
/// On web `compute` lowers to a Web Worker, which has both heavier
/// startup cost and more restrictive payload requirements; the app's
/// mock workloads are small enough there that we just run inline.
Future<R> runOffMain<Q, R>(
  ComputeCallback<Q, R> callback,
  Q message, {
  int? heuristicSize,
  int threshold = 2000,
  String? debugLabel,
}) {
  if (kIsWeb) {
    return Future<R>.sync(() => callback(message));
  }
  if (heuristicSize != null && heuristicSize < threshold) {
    return Future<R>.sync(() => callback(message));
  }
  return compute<Q, R>(callback, message, debugLabel: debugLabel);
}
