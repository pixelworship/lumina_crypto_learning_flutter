import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

/// A discrete real-world event (earnings, tweet, regulator filing, ...) that
/// is overlaid on the price timeline as a small badge.
///
/// Instances are created from a `MarketEventTemplate` in
/// `data/services/market_event_catalog.dart` — the template provides the
/// look and copy, the instance pins it to a specific [timestamp].
class MarketEvent extends Equatable {
  const MarketEvent({
    required this.id,
    required this.timestamp,
    required this.label,
    required this.color,
    required this.title,
    required this.body,
    this.icon,
  });

  /// Unique id (template + timestamp), used for keying and modal routing.
  final String id;
  final DateTime timestamp;

  /// Single character (or short string) shown inside the badge when [icon]
  /// is null.
  final String label;

  /// Badge background colour.
  final Color color;

  /// Modal title, e.g. "Earnings call".
  final String title;

  /// Modal body, e.g. "Q4 EPS $1.32 vs $1.21 est.".
  final String body;

  /// Optional icon shown inside the badge instead of [label]. Used for
  /// brand-y events like an X/Twitter post.
  final IconData? icon;

  @override
  List<Object?> get props =>
      <Object?>[id, timestamp, label, color, title, body, icon];
}
