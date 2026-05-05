import '../models/market_event.dart';
import '../services/chart_events_api.dart';

/// Thin facade over [ChartEventsApi].
///
/// Mirrors the `*Repository` pattern used elsewhere (e.g. `TickRepository`,
/// `HistoricalTickRepository`) so the chart bloc consumes a repository
/// rather than a raw HTTP client. Today this is a straight pass-through;
/// the seam exists so a cache layer (or Supabase Realtime subscription)
/// can be added later without touching the bloc.
class ChartEventsRepository {
  ChartEventsRepository({required ChartEventsApi api}) : _api = api;

  final ChartEventsApi _api;

  /// Window query — see [ChartEventsApi.fetchEventsInRange].
  Future<List<MarketEvent>> fetchEventsInRange({
    required String symbol,
    required DateTime from,
    required DateTime to,
    int limit = 200,
  }) {
    return _api.fetchEventsInRange(
      symbol: symbol,
      from: from,
      to: to,
      limit: limit,
    );
  }

  /// Delta query — see [ChartEventsApi.fetchEventsSince].
  Future<List<MarketEvent>> fetchEventsSince({
    required String symbol,
    required DateTime since,
    int limit = 500,
  }) {
    return _api.fetchEventsSince(
      symbol: symbol,
      since: since,
      limit: limit,
    );
  }
}
