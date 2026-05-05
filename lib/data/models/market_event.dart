import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// A discrete real-world event (earnings, tweet, regulator filing, ...) that
/// is overlaid on the price timeline as a small badge.
///
/// Sourced from the Lumina events API (`_x/api`, backed by the Supabase
/// `chart_events` table). The API stores `id`, `asset`, `timestamp`,
/// `title`, `body`, `link`; the `label`/`color`/`icon` fields are
/// presentation-only defaults filled in by the API client.
class MarketEvent extends Equatable {
  const MarketEvent({
    required this.id,
    required this.timestamp,
    required this.label,
    required this.color,
    required this.title,
    this.body,
    this.link,
    this.icon,
  });

  /// Unique id, used for keying and modal routing. Stringified from the
  /// `chart_events.id` int8 column at the API boundary.
  final String id;
  final DateTime timestamp;

  /// Single character (or short string) shown inside the badge when [icon]
  /// is null.
  final String label;

  /// Badge background colour.
  final Color color;

  /// Modal title, e.g. "Spot ETF inflow".
  final String title;

  /// Modal body. Nullable — the column is optional in `chart_events`.
  final String? body;

  /// Optional source URL — opened from the event detail modal.
  final String? link;

  /// Optional icon shown inside the badge instead of [label]. Used for
  /// brand-y events like an X/Twitter post.
  final IconData? icon;

  @override
  List<Object?> get props =>
      <Object?>[id, timestamp, label, color, title, body, link, icon];
}
