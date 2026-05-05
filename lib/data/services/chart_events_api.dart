import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/market_event.dart';

/// Two intentional shapes for reading `chart_events`:
///
/// * [fetchEventsInRange] — "give me everything in `[from, to]`". Used
///   for the initial chart load and history extension.
/// * [fetchEventsSince] — "give me everything created strictly after
///   `since`". Used by the chart's 1s poll. Strict-greater-than
///   semantics on the server mean clients can use the latest event
///   timestamp they've seen as the next cursor without an off-by-one
///   fudge.
///
/// Implementations MUST NOT throw on transport errors — they should
/// log and return an empty list so the chart degrades gracefully.
abstract class ChartEventsApi {
  /// Window query. Both [from] and [to] are required so callers can't
  /// accidentally tail forever; if you want "from now backwards", pass
  /// [DateTime.now] as `to`. Returned ordering is ascending by
  /// timestamp regardless of how the server orders the rows.
  Future<List<MarketEvent>> fetchEventsInRange({
    required String symbol,
    required DateTime from,
    required DateTime to,
    int limit = 200,
  });

  /// Delta query. Returns events with `timestamp > since`, ascending.
  /// The default [limit] is higher than the window query's so a
  /// backgrounded client can catch up in one round-trip when it
  /// returns to the foreground.
  Future<List<MarketEvent>> fetchEventsSince({
    required String symbol,
    required DateTime since,
    int limit = 500,
  });
}

/// Real implementation that hits the Express server in `_x/api`.
///
/// Configure the base URL via `--dart-define=EVENTS_API_BASE_URL=...`;
/// `lib/app.dart` reads the define and passes it here. Default is
/// `http://localhost:4001`, which works for the iOS simulator, macOS,
/// and the web build pointed at the same machine.
class HttpChartEventsApi implements ChartEventsApi {
  HttpChartEventsApi({
    required String baseUrl,
    http.Client? client,
    Duration timeout = const Duration(seconds: 5),
  })  : _baseUrl = _trimTrailingSlash(baseUrl),
        _client = client ?? http.Client(),
        _timeout = timeout;

  final String _baseUrl;
  final http.Client _client;
  final Duration _timeout;

  /// Single neutral fill for every API-sourced event. The API doesn't
  /// store per-event styling, so we standardize on this blue-grey to
  /// keep the chart readable without cluttering it with color noise.
  static const Color _kNeutralColor = Color(0xFF455A64);

  /// One badge label for everything. The icon ([Icons.article])
  /// supersedes the label in [_BadgeGlyph] when set, so the actual
  /// glyph rendered is the article icon.
  static const String _kNeutralLabel = 'E';

  static const IconData _kNeutralIcon = Icons.article;

  @override
  Future<List<MarketEvent>> fetchEventsInRange({
    required String symbol,
    required DateTime from,
    required DateTime to,
    int limit = 200,
  }) {
    final Uri uri = Uri.parse('$_baseUrl/v1/events').replace(
      queryParameters: <String, String>{
        'asset': symbol.toUpperCase(),
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
        'limit': limit.toString(),
      },
    );
    return _fetch(uri, debugLabel: 'events range');
  }

  @override
  Future<List<MarketEvent>> fetchEventsSince({
    required String symbol,
    required DateTime since,
    int limit = 500,
  }) {
    final Uri uri = Uri.parse('$_baseUrl/v1/events/since').replace(
      queryParameters: <String, String>{
        'asset': symbol.toUpperCase(),
        'since': since.toUtc().toIso8601String(),
        'limit': limit.toString(),
      },
    );
    return _fetch(uri, debugLabel: 'events since');
  }

  /// Shared fetch + decode + sort path. Both endpoints return the same
  /// `{events: [...]}` envelope; the URL is what differs.
  Future<List<MarketEvent>> _fetch(
    Uri uri, {
    required String debugLabel,
  }) async {
    try {
      final http.Response response =
          await _client.get(uri).timeout(_timeout);
      if (response.statusCode != 200) {
        if (kDebugMode) {
          debugPrint(
            '$debugLabel ${response.statusCode}: ${response.body}',
          );
        }
        return const <MarketEvent>[];
      }
      final dynamic decoded = json.decode(response.body);
      if (decoded is! Map<String, dynamic>) return const <MarketEvent>[];
      final dynamic raw = decoded['events'];
      if (raw is! List) return const <MarketEvent>[];

      final List<MarketEvent> out = <MarketEvent>[];
      for (final dynamic row in raw) {
        if (row is! Map<String, dynamic>) continue;
        final MarketEvent? event = _toMarketEvent(row);
        if (event != null) out.add(event);
      }
      // The window endpoint returns descending; the delta endpoint
      // returns ascending. Either way the chart wants ascending, so
      // normalize here rather than leaning on the server contract.
      out.sort(
        (MarketEvent a, MarketEvent b) =>
            a.timestamp.compareTo(b.timestamp),
      );
      return out;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('$debugLabel failed: $e\n$st');
      }
      return const <MarketEvent>[];
    }
  }

  static MarketEvent? _toMarketEvent(Map<String, dynamic> row) {
    final dynamic id = row['id'];
    final dynamic timestamp = row['timestamp'];
    final dynamic title = row['title'];
    if (id == null || timestamp is! String || title is! String) {
      return null;
    }
    final DateTime? parsedTs = DateTime.tryParse(timestamp);
    if (parsedTs == null) return null;

    return MarketEvent(
      id: id.toString(),
      timestamp: parsedTs.toUtc(),
      label: _kNeutralLabel,
      color: _kNeutralColor,
      icon: _kNeutralIcon,
      title: title,
      body: row['body'] is String ? row['body'] as String : null,
      link: row['link'] is String ? row['link'] as String : null,
    );
  }

  static String _trimTrailingSlash(String s) {
    if (s.isEmpty) return s;
    int end = s.length;
    while (end > 0 && s.codeUnitAt(end - 1) == 0x2F /* '/' */) {
      end--;
    }
    return s.substring(0, end);
  }
}
