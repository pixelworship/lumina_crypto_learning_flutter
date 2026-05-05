import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:url_launcher/url_launcher.dart';

import '../../../data/models/candle.dart';
import '../../../data/models/market_event.dart';
import '../../../data/models/timeframe.dart';
import '../../../design_system/lumina_ui.dart';

/// Tappable event badges aligned with the price timeline.
///
/// Events that overlap horizontally are collapsed into a single
/// cluster — the most recent event in that cluster renders as the
/// primary badge with a `+N` companion sitting next to it. Tapping
/// a single-event cluster opens its detail dialog directly; tapping
/// a multi-event cluster surfaces a popover listing every event so
/// the user can pick which to inspect.
///
/// The chart never stacks badges vertically regardless of event
/// density: the row is always one badge tall.
class EventMarkerOverlay extends StatelessWidget {
  const EventMarkerOverlay({
    super.key,
    required this.events,
    required this.candles,
    required this.timeframe,
    required this.firstVisibleIndex,
    required this.candleWidth,
    required this.plotArea,
  });

  final List<MarketEvent> events;
  final List<Candle> candles;
  final Timeframe timeframe;
  final double firstVisibleIndex;
  final double candleWidth;
  final Rect plotArea;

  static const double _badgeSize = 22;
  static const double _badgeSpacing = 4;
  static const double _bottomMargin = 4;

  /// Returns the (possibly fractional) candle-index slot where
  /// [event] belongs, or null if the event predates the visible
  /// history.
  double? _slotForEvent(MarketEvent event) {
    if (event.timestamp.isBefore(candles.first.timestamp)) {
      return null;
    }
    for (int i = candles.length - 1; i >= 0; i--) {
      final Candle candle = candles[i];
      if (!candle.timestamp.isAfter(event.timestamp)) {
        final DateTime nextTs = i + 1 < candles.length
            ? candles[i + 1].timestamp
            : candle.timestamp.add(timeframe.duration);
        final int spanMs =
            nextTs.difference(candle.timestamp).inMilliseconds;
        if (spanMs <= 0) return i + 0.5;
        final double fraction = event.timestamp
                .difference(candle.timestamp)
                .inMilliseconds /
            spanMs;
        return i + fraction.clamp(0.0, 1.0);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty || candles.isEmpty || candleWidth <= 0) {
      return const SizedBox.shrink();
    }
    if (timeframe.duration.inMilliseconds <= 0) {
      return const SizedBox.shrink();
    }

    // Resolve every event's centerX and drop the ones that fall
    // entirely off-screen. Sort left→right so cluster building is
    // a single linear sweep.
    final List<_PositionedEvent> positioned = <_PositionedEvent>[];
    for (final MarketEvent event in events) {
      final double? slot = _slotForEvent(event);
      if (slot == null) continue;
      final double centerX =
          plotArea.left + (slot - firstVisibleIndex) * candleWidth;
      if (centerX < plotArea.left - _badgeSize ||
          centerX > plotArea.right + _badgeSize * 2) {
        continue;
      }
      positioned.add(_PositionedEvent(event: event, centerX: centerX));
    }
    positioned.sort(
      (_PositionedEvent a, _PositionedEvent b) =>
          a.centerX.compareTo(b.centerX),
    );

    // Cluster overlapping events. Two events join the same cluster
    // when their centerX positions are within one badge-width — i.e.
    // their badges would overlap if drawn side-by-side. The cluster
    // anchors at the FIRST event's x so the row reads left-to-right.
    final List<_EventCluster> clusters = <_EventCluster>[];
    for (final _PositionedEvent pe in positioned) {
      if (clusters.isEmpty ||
          pe.centerX - clusters.last._lastCenterX > _badgeSize) {
        clusters.add(
          _EventCluster(
            anchorCenterX: pe.centerX,
            events: <MarketEvent>[pe.event],
          ).._lastCenterX = pe.centerX,
        );
      } else {
        clusters.last.events.add(pe.event);
        clusters.last._lastCenterX = pe.centerX;
      }
    }

    final double top = plotArea.bottom - _bottomMargin - _badgeSize;
    return Stack(
      children: <Widget>[
        for (final _EventCluster cluster in clusters)
          Positioned(
            left: cluster.anchorCenterX - _badgeSize / 2,
            top: top,
            child: _ClusterBadge(cluster: cluster),
          ),
      ],
    );
  }
}

class _PositionedEvent {
  const _PositionedEvent({required this.event, required this.centerX});
  final MarketEvent event;
  final double centerX;
}

class _EventCluster {
  _EventCluster({required this.anchorCenterX, required this.events});

  /// Where the primary badge is anchored. Always equals the
  /// chronologically-first event's centerX (the row reads
  /// left-to-right).
  final double anchorCenterX;
  final List<MarketEvent> events;

  /// Internal: the centerX of the most recently absorbed event.
  /// Used during cluster building to decide whether the next event
  /// is close enough to join.
  double _lastCenterX = 0;

  /// The event surfaced as the primary visible badge: the most
  /// recent (latest timestamp) so the freshest news always shows.
  MarketEvent get primary => events.reduce(
    (MarketEvent a, MarketEvent b) =>
        a.timestamp.isAfter(b.timestamp) ? a : b,
  );
}

/// The horizontal row drawn for one cluster: primary event badge +
/// (optional) `+N` badge. Both targets are tappable.
class _ClusterBadge extends StatelessWidget {
  const _ClusterBadge({required this.cluster});

  final _EventCluster cluster;

  @override
  Widget build(BuildContext context) {
    final int extra = cluster.events.length - 1;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        _EventBadge(
          event: cluster.primary,
          onTap: () => _handleTap(context),
        ),
        if (extra > 0) ...<Widget>[
          const SizedBox(width: EventMarkerOverlay._badgeSpacing),
          _MoreBadge(count: extra, onTap: () => _handleTap(context)),
        ],
      ],
    );
  }

  Future<void> _handleTap(BuildContext context) async {
    if (cluster.events.length == 1) {
      _showEventModal(context, cluster.events.first);
      return;
    }
    final MarketEvent? selected = await _showClusterMenu(context);
    if (selected != null && context.mounted) {
      _showEventModal(context, selected);
    }
  }

  /// Pops a fly-out anchored to the cluster badge listing every
  /// event in chronological order (newest first). Returning the
  /// selected event lets the caller pop a detail dialog for it.
  Future<MarketEvent?> _showClusterMenu(BuildContext context) async {
    final LuminaTokens t = context.tokens;
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    final RenderBox? overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return null;

    final Offset topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final Offset bottomRight = box.localToGlobal(
      box.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );

    final List<MarketEvent> sorted = List<MarketEvent>.from(cluster.events)
      ..sort(
        (MarketEvent a, MarketEvent b) =>
            b.timestamp.compareTo(a.timestamp),
      );

    return showMenu<MarketEvent>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(topLeft, bottomRight),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<MarketEvent>>[
        for (final MarketEvent event in sorted)
          PopupMenuItem<MarketEvent>(
            value: event,
            padding: EdgeInsets.symmetric(
              horizontal: t.spacing.md,
              vertical: t.spacing.xs + 2,
            ),
            child: _EventMenuItem(event: event),
          ),
      ],
    );
  }
}

/// Compact "+N" indicator that sits next to a multi-event cluster's
/// primary badge. Visually distinct from real event badges (uses
/// surface fill + a neutral border) so users read it as
/// "more available", not as another event.
class _MoreBadge extends StatelessWidget {
  const _MoreBadge({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.all(t.radii.xs),
        child: Container(
          width: EventMarkerOverlay._badgeSize,
          height: EventMarkerOverlay._badgeSize,
          decoration: BoxDecoration(
            color: t.colors.surfaceRaised,
            borderRadius: BorderRadius.all(t.radii.xs),
            border: Border.all(color: t.colors.borderDefault),
            boxShadow: t.elevation.sm,
          ),
          alignment: Alignment.center,
          child: Text(
            '+$count',
            style: t.typography.labelSm.copyWith(
              color: t.colors.contentPrimary,
              letterSpacing: 0,
              height: 1.0,
            ),
          ),
        ),
      ),
    );
  }
}

/// Single row inside the cluster popover: event badge + title.
class _EventMenuItem extends StatelessWidget {
  const _EventMenuItem({required this.event});

  final MarketEvent event;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _BadgeGlyph(event: event, size: 22, fontSize: 12),
        SizedBox(width: t.spacing.sm + 2),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(
            event.title,
            style: t.typography.bodySm.copyWith(
              color: t.colors.contentPrimary,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _EventBadge extends StatelessWidget {
  const _EventBadge({required this.event, required this.onTap});

  final MarketEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.all(t.radii.xs),
        child: Tooltip(
          message: event.title,
          waitDuration: const Duration(milliseconds: 400),
          child: _BadgeGlyph(event: event),
        ),
      ),
    );
  }
}

class _BadgeGlyph extends StatelessWidget {
  const _BadgeGlyph({
    required this.event,
    this.size = 22,
    this.fontSize = 12,
  });

  final MarketEvent event;
  final double size;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    final IconData? icon = event.icon;
    // Event glyphs sit on saturated brand-event fills (red, green,
    // blue, etc.) defined in the market event catalog. White content
    // is intentional in both themes — `contentInverse` would invert
    // to dark in dark mode and become unreadable on those dark fills.
    const Color glyphColor = Colors.white;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: event.color,
        borderRadius: BorderRadius.all(t.radii.xs),
        border: Border.all(
          color: glyphColor.withValues(alpha: 0.85),
          width: 1,
        ),
        boxShadow: t.elevation.sm,
      ),
      alignment: Alignment.center,
      child: icon != null
          ? Icon(icon, size: fontSize + 2, color: glyphColor)
          : Text(
              event.label,
              style: t.typography.labelSm.copyWith(
                color: glyphColor,
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                height: 1.0,
              ),
            ),
    );
  }
}

void _showEventModal(BuildContext context, MarketEvent event) {
  final intl.DateFormat dateFmt = intl.DateFormat('MMM d, h:mm a');
  showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) {
      final LuminaTokens t = dialogContext.tokens;
      final String? body = event.body;
      final String? link = event.link;
      return AlertDialog(
        backgroundColor: t.colors.surfaceRaised,
        title: Row(
          children: <Widget>[
            _BadgeGlyph(event: event, size: 28, fontSize: 14),
            SizedBox(width: t.spacing.md),
            Expanded(child: Text(event.title)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              dateFmt.format(event.timestamp),
              style: t.typography.bodySm.copyWith(
                color: t.colors.contentTertiary,
              ),
            ),
            if (body != null && body.isNotEmpty) ...<Widget>[
              SizedBox(height: t.spacing.md),
              Text(
                body,
                style: t.typography.bodyMd.copyWith(
                  color: t.colors.contentPrimary,
                ),
              ),
            ],
          ],
        ),
        actions: <Widget>[
          if (link != null && link.isNotEmpty)
            TextButton.icon(
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Open link'),
              onPressed: () => _openExternal(link),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

/// Tries to open [url] in the platform's default external handler.
/// Failures are intentionally swallowed (logged in debug) — the modal's
/// primary purpose is showing the body, not navigating.
Future<void> _openExternal(String url) async {
  final Uri? uri = Uri.tryParse(url);
  if (uri == null) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e, st) {
    if (kDebugMode) {
      debugPrint('event link open failed: $e\n$st');
    }
  }
}
