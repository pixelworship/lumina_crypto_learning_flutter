import 'dart:math';

import 'package:flutter/material.dart';

import '../models/market_event.dart';

/// Static template for a [MarketEvent]. The catalog below holds ~a dozen
/// of these; spawning picks one at random and stamps it with a timestamp.
@immutable
class MarketEventTemplate {
  const MarketEventTemplate({
    required this.code,
    required this.label,
    required this.color,
    required this.title,
    required this.body,
    this.icon,
  });

  /// Stable short id used in [MarketEvent.id] (e.g. "earnings").
  final String code;
  final String label;
  final Color color;
  final String title;
  final String body;
  final IconData? icon;

  MarketEvent instantiate({
    required DateTime timestamp,
    required Random random,
  }) {
    final String salt = random.nextInt(1 << 32).toRadixString(36);
    return MarketEvent(
      id: '$code-${timestamp.microsecondsSinceEpoch}-$salt',
      timestamp: timestamp,
      label: label,
      color: color,
      title: title,
      body: body,
      icon: icon,
    );
  }
}

/// Curated mock event templates. Add or tweak freely — all colours come
/// from material shades so they sit reasonably on a dark chart.
const List<MarketEventTemplate> kMarketEventCatalog = <MarketEventTemplate>[
  MarketEventTemplate(
    code: 'earnings',
    label: 'E',
    color: Color(0xFF2E7D32),
    title: 'Earnings call',
    body:
        'Q4 EPS came in at \$1.32 vs \$1.21 est. Revenue beat by 4%; '
        'guidance raised for next quarter.',
  ),
  MarketEventTemplate(
    code: 'elon-x',
    label: 'X',
    color: Color(0xFF111111),
    title: 'Elon Musk on X',
    body:
        '"scam altman!" — @elonmusk · 14m\n\n'
        '12.4k reposts · 88k likes',
    icon: Icons.close,
  ),
  MarketEventTemplate(
    code: 'fomc',
    label: 'F',
    color: Color(0xFF1565C0),
    title: 'FOMC decision',
    body:
        'Fed holds the target range at 5.25–5.50%. Powell signals two '
        'cuts on the table for H2.',
  ),
  MarketEventTemplate(
    code: 'sec',
    label: 'S',
    color: Color(0xFF6A1B9A),
    title: 'SEC 13F filing',
    body:
        'Berkshire disclosed a new 1.2M-share position. Filing also '
        'reveals a fully exited stake in a peer name.',
  ),
  MarketEventTemplate(
    code: 'analyst',
    label: 'A',
    color: Color(0xFFEF6C00),
    title: 'Analyst upgrade',
    body:
        'Goldman Sachs upgrades to Buy from Neutral. Price target '
        'raised to \$250 from \$198 citing AI revenue tailwinds.',
  ),
  MarketEventTemplate(
    code: 'merger',
    label: 'M',
    color: Color(0xFF00838F),
    title: 'M&A rumour',
    body:
        'Bloomberg sources: takeover talks underway with a mid-cap '
        'rival at a 30% premium. Talks described as "advanced".',
  ),
  MarketEventTemplate(
    code: 'dividend',
    label: 'D',
    color: Color(0xFF388E3C),
    title: 'Dividend declared',
    body:
        'Board declared a quarterly dividend of \$0.42/share, payable '
        'June 14 to shareholders of record May 31.',
  ),
  MarketEventTemplate(
    code: 'recall',
    label: 'R',
    color: Color(0xFFC62828),
    title: 'Product recall',
    body:
        'Voluntary recall of ~120k units announced after a supplier '
        'defect. Estimated charge: \$45M.',
  ),
  MarketEventTemplate(
    code: 'lawsuit',
    label: 'L',
    color: Color(0xFFAD1457),
    title: 'Class action filed',
    body:
        'Securities class action filed in the Northern District of '
        'California alleging misleading guidance.',
  ),
  MarketEventTemplate(
    code: 'news',
    label: 'N',
    color: Color(0xFF455A64),
    title: 'WSJ exclusive',
    body:
        'Reporters say insider selling spiked in the two weeks ahead '
        'of the upcoming print. Three named officers participated.',
  ),
  MarketEventTemplate(
    code: 'ceo',
    label: 'C',
    color: Color(0xFF5D4037),
    title: 'CEO transition',
    body:
        'CEO Jane Doe steps down effective immediately. Board promotes '
        'COO to interim CEO; external search underway.',
  ),
  MarketEventTemplate(
    code: 'ipo',
    label: 'I',
    color: Color(0xFF4527A0),
    title: 'Subsidiary IPO priced',
    body:
        'Subsidiary priced at \$42, top of the range. 2.4x '
        'oversubscribed; trading begins tomorrow under ticker NEWCO.',
  ),
];

/// Picks a random template from [kMarketEventCatalog] and stamps it at
/// [timestamp].
MarketEvent randomMarketEvent({
  required DateTime timestamp,
  required Random random,
}) {
  final MarketEventTemplate template =
      kMarketEventCatalog[random.nextInt(kMarketEventCatalog.length)];
  return template.instantiate(timestamp: timestamp, random: random);
}
