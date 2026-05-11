import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

import '../../../core/utils/formatters.dart';
import '../../../data/models/candle.dart';
import '../../../data/models/fill.dart';
import '../../../data/models/timeframe.dart';
import '../../../design_system/lumina_ui.dart';

/// Tappable user-trade markers anchored at each fill's price on the
/// candlestick chart.
///
/// Twin to `EventMarkerOverlay` — same per-fill culling + cluster-on-
/// overlap idiom — but anchors vertically at [Fill.price] (mapped
/// through the chart's active price range) instead of pinning to the
/// bottom strip. The horizontal slot resolution mirrors
/// [EventMarkerOverlay] so the two layers share the same time→x
/// understanding without inheriting a base class (composition would
/// pull each one's identity into the same hierarchy and complicate
/// per-overlay tweaks).
///
/// Tapping a single-fill marker opens the inspect modal directly.
/// Tapping a multi-fill cluster surfaces a popover so the user can
/// choose which fill to inspect.
class FillMarkerOverlay extends StatelessWidget {
  const FillMarkerOverlay({
    super.key,
    required this.fills,
    required this.candles,
    required this.timeframe,
    required this.firstVisibleIndex,
    required this.candleWidth,
    required this.plotArea,
    required this.priceRange,
  });

  final List<Fill> fills;
  final List<Candle> candles;
  final Timeframe timeframe;
  final double firstVisibleIndex;
  final double candleWidth;
  final Rect plotArea;

  /// `(min, max)` price band the renderer is currently mapping y to.
  /// Pulled directly from `_CustomChartState`'s computed range so
  /// markers track auto-scale, manual-pan, and frozen-range modes
  /// without re-deriving the math.
  final (double, double) priceRange;

  static const double _markerSize = 22;
  static const double _markerSpacing = 4;

  /// Returns the (possibly fractional) candle-index slot where [fill]
  /// should anchor horizontally, or null if it predates the visible
  /// history. Mirrors `EventMarkerOverlay._slotForEvent` deliberately
  /// — same time-to-slot mapping for both overlays so a fill and an
  /// event at the same timestamp line up vertically.
  double? _slotForFill(Fill fill) {
    if (candles.isEmpty) return null;
    if (fill.timestamp.isBefore(candles.first.timestamp)) return null;
    for (int i = candles.length - 1; i >= 0; i--) {
      final Candle candle = candles[i];
      if (!candle.timestamp.isAfter(fill.timestamp)) {
        final DateTime nextTs = i + 1 < candles.length
            ? candles[i + 1].timestamp
            : candle.timestamp.add(timeframe.duration);
        final int spanMs =
            nextTs.difference(candle.timestamp).inMilliseconds;
        if (spanMs <= 0) return i + 0.5;
        final double fraction = fill.timestamp
                .difference(candle.timestamp)
                .inMilliseconds /
            spanMs;
        return i + fraction.clamp(0.0, 1.0);
      }
    }
    return null;
  }

  /// Maps [price] to a y-coordinate inside [plotArea] using the
  /// renderer's active price range. Identical formula to the one
  /// `CandlePainter` applies to candle bodies so a marker at the
  /// fill's price lands exactly on the candle wick at that price.
  double _yForPrice(double price) {
    final double minPrice = priceRange.$1;
    final double maxPrice = priceRange.$2;
    if (maxPrice <= minPrice) return plotArea.top + plotArea.height / 2;
    final double clamped = price.clamp(minPrice, maxPrice);
    final double ratio = (clamped - minPrice) / (maxPrice - minPrice);
    return plotArea.bottom - ratio * plotArea.height;
  }

  @override
  Widget build(BuildContext context) {
    if (fills.isEmpty || candles.isEmpty || candleWidth <= 0) {
      return const SizedBox.shrink();
    }
    if (timeframe.duration.inMilliseconds <= 0) {
      return const SizedBox.shrink();
    }

    // Resolve every fill's centerX/centerY and drop the ones that
    // fall entirely off-screen. We only cluster fills whose y values
    // are also close together (within a marker-height) — fills that
    // happen at the same time but very different prices stay
    // visually distinct.
    final List<_PositionedFill> positioned = <_PositionedFill>[];
    for (final Fill fill in fills) {
      final double? slot = _slotForFill(fill);
      if (slot == null) continue;
      final double centerX =
          plotArea.left + (slot - firstVisibleIndex) * candleWidth;
      if (centerX < plotArea.left - _markerSize ||
          centerX > plotArea.right + _markerSize * 2) {
        continue;
      }
      final double centerY = _yForPrice(fill.price);
      positioned.add(
        _PositionedFill(fill: fill, centerX: centerX, centerY: centerY),
      );
    }
    if (positioned.isEmpty) return const SizedBox.shrink();

    positioned.sort(
      (_PositionedFill a, _PositionedFill b) =>
          a.centerX.compareTo(b.centerX),
    );

    // Cluster overlapping fills: same logic as event overlay but with
    // an extra y-proximity check so a same-second buy and sell at
    // very different prices don't collapse into one marker.
    final List<_FillCluster> clusters = <_FillCluster>[];
    for (final _PositionedFill pf in positioned) {
      final _FillCluster? last = clusters.isEmpty ? null : clusters.last;
      final bool xClose = last != null &&
          pf.centerX - last._lastCenterX <= _markerSize;
      final bool yClose = last != null &&
          (pf.centerY - last.anchorCenterY).abs() <= _markerSize;
      if (last != null && xClose && yClose) {
        last.fills.add(pf.fill);
        last._lastCenterX = pf.centerX;
      } else {
        clusters.add(
          _FillCluster(
            anchorCenterX: pf.centerX,
            anchorCenterY: pf.centerY,
            fills: <Fill>[pf.fill],
          ).._lastCenterX = pf.centerX,
        );
      }
    }

    // Clip to the plot area so markers near the right edge get cut off
    // at the price-label gutter — same behavior as the candle painter
    // (`canvas.clipRect(plotArea)`). Otherwise a fill anchored just
    // before the live edge can render on top of the price labels.
    return ClipRect(
      clipper: _PlotAreaClipper(plotArea),
      child: Stack(
        children: <Widget>[
          for (final _FillCluster cluster in clusters)
            Positioned(
              left: cluster.anchorCenterX - _markerSize / 2,
              top: cluster.anchorCenterY - _markerSize / 2,
              child: _ClusterMarker(cluster: cluster),
            ),
        ],
      ),
    );
  }
}

/// Clips the overlay's painted output (and hit tests) to the chart's
/// plot area, so markers can't spill into the right-side price gutter.
class _PlotAreaClipper extends CustomClipper<Rect> {
  const _PlotAreaClipper(this.plotArea);

  final Rect plotArea;

  @override
  Rect getClip(Size size) => plotArea;

  @override
  bool shouldReclip(_PlotAreaClipper oldClipper) =>
      oldClipper.plotArea != plotArea;
}

class _PositionedFill {
  const _PositionedFill({
    required this.fill,
    required this.centerX,
    required this.centerY,
  });

  final Fill fill;
  final double centerX;
  final double centerY;
}

class _FillCluster {
  _FillCluster({
    required this.anchorCenterX,
    required this.anchorCenterY,
    required this.fills,
  });

  final double anchorCenterX;
  final double anchorCenterY;
  final List<Fill> fills;

  double _lastCenterX = 0;

  /// Latest fill in the cluster (most recent timestamp). Surfaced as
  /// the primary marker glyph so the freshest purchase reads first.
  Fill get primary => fills.reduce(
        (Fill a, Fill b) => a.timestamp.isAfter(b.timestamp) ? a : b,
      );
}

/// Visual + interaction wrapper around a single cluster: primary
/// marker glyph + (optional) `+N` companion. Both targets are
/// tappable.
class _ClusterMarker extends StatelessWidget {
  const _ClusterMarker({required this.cluster});

  final _FillCluster cluster;

  @override
  Widget build(BuildContext context) {
    final int extra = cluster.fills.length - 1;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        _FillMarker(
          fill: cluster.primary,
          onTap: () => _handleTap(context),
        ),
        if (extra > 0) ...<Widget>[
          const SizedBox(width: FillMarkerOverlay._markerSpacing),
          _MoreBadge(count: extra, onTap: () => _handleTap(context)),
        ],
      ],
    );
  }

  Future<void> _handleTap(BuildContext context) async {
    if (cluster.fills.length == 1) {
      _showFillModal(context, cluster.fills.first);
      return;
    }
    final Fill? selected = await _showClusterMenu(context);
    if (selected != null && context.mounted) {
      _showFillModal(context, selected);
    }
  }

  /// Pops a fly-out anchored to the cluster marker listing every fill
  /// (newest first). Returning the picked fill lets the caller open
  /// its detail modal.
  Future<Fill?> _showClusterMenu(BuildContext context) async {
    final RenderBox? box = context.findRenderObject() as RenderBox?;
    final RenderBox? overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return null;

    final Offset topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final Offset bottomRight = box.localToGlobal(
      box.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );

    final List<Fill> sorted = List<Fill>.from(cluster.fills)
      ..sort((Fill a, Fill b) => b.timestamp.compareTo(a.timestamp));

    return showMenu<Fill>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(topLeft, bottomRight),
        Offset.zero & overlay.size,
      ),
      items: <PopupMenuEntry<Fill>>[
        for (final Fill f in sorted)
          PopupMenuItem<Fill>(
            value: f,
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 6,
            ),
            child: _FillMenuItem(fill: f),
          ),
      ],
    );
  }
}

/// Compact "+N" indicator next to a multi-fill cluster's primary
/// marker. Visually distinct from real fill glyphs so users read it
/// as "more available", not as another fill.
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
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: t.colors.surfaceRaised,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: t.colors.borderDefault),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            '+$count',
            style: t.typography.numericSm.copyWith(
              color: t.colors.contentPrimary,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
              height: 1.0,
            ),
          ),
        ),
      ),
    );
  }
}

/// A single row inside the multi-fill cluster popover: marker glyph +
/// "Bought 0.10 BTC @ $63,940".
class _FillMenuItem extends StatelessWidget {
  const _FillMenuItem({required this.fill});

  final Fill fill;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    // The popup menu hands us a bounded but variable width depending on
    // screen size. Wrapping the label in `Flexible` (rather than a fixed
    // `ConstrainedBox(maxWidth: 240)`) lets the text ellipsize against the
    // *actual* available width, so a narrow phone layout can't push the row
    // a few pixels past the menu edge.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _MarkerGlyph(fill: fill, size: 20, fontSize: 10),
          SizedBox(width: t.spacing.sm + 2),
          Flexible(
            child: Text(
              _shortFillLabel(fill),
              // Mono so the price column lines up across rows when a
              // cluster expands ("@ $63,940" / "@ $63,941" / "@ $63,938").
              style: t.typography.numericSm.copyWith(
                fontSize: 14,
                color: t.colors.contentPrimary,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
        ],
      ),
    );
  }
}

/// The tap target wrapper around a [_MarkerGlyph]. A separate widget
/// (rather than wrapping the glyph directly with InkWell) so the
/// hover/tooltip surface stays scoped to the marker bounds.
class _FillMarker extends StatelessWidget {
  const _FillMarker({required this.fill, required this.onTap});

  final Fill fill;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Tooltip(
          message: _shortFillLabel(fill),
          waitDuration: const Duration(milliseconds: 400),
          child: _MarkerGlyph(fill: fill),
        ),
      ),
    );
  }
}

/// The visual marker itself: a filled triangle inside a rounded
/// pill. Buys point up; sells point down. Color matches the chart's
/// bullish/bearish accent so the marker reads as a familiar
/// direction even without the inset triangle.
class _MarkerGlyph extends StatelessWidget {
  const _MarkerGlyph({
    required this.fill,
    this.size = 22,
    this.fontSize = 12,
  });

  final Fill fill;
  final double size;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    final bool isBuy = fill.side == FillSide.buy;
    final Color glyphColor =
        isBuy ? t.colors.chartCandleBullish : t.colors.chartCandleBearish;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: glyphColor,
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.92),
          width: 1.2,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 5,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(
        isBuy ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
        size: fontSize + 1,
        color: Colors.white,
      ),
    );
  }
}

String _shortFillLabel(Fill fill) {
  final String verb = fill.side == FillSide.buy ? 'Bought' : 'Sold';
  return '$verb ${Formatters.crypto(fill.sizeBase)} ${fill.symbol} '
      '@ ${Formatters.compactCurrency(fill.price)}';
}

void _showFillModal(BuildContext context, Fill fill) {
  final intl.DateFormat dateFmt = intl.DateFormat('MMM d, h:mm a');
  showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) {
      final LuminaTokens t = dialogContext.tokens;
      final bool isBuy = fill.side == FillSide.buy;
      final String title = isBuy ? 'Purchase' : 'Sale';
      return AlertDialog(
        backgroundColor: t.colors.surfaceRaised,
        title: Row(
          children: <Widget>[
            _MarkerGlyph(fill: fill, size: 28, fontSize: 14),
            SizedBox(width: t.spacing.md),
            Expanded(child: Text(title)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              dateFmt.format(fill.timestamp),
              style: t.typography.bodySm.copyWith(
                color: t.colors.contentTertiary,
              ),
            ),
            SizedBox(height: t.spacing.md),
            _Row(
              label: 'Size',
              value: '${Formatters.crypto(fill.sizeBase)} ${fill.symbol}',
            ),
            SizedBox(height: t.spacing.xs + 2),
            _Row(
              label: 'Price',
              value:
                  '${Formatters.compactCurrency(fill.price)} ${fill.quoteSymbol}',
            ),
            SizedBox(height: t.spacing.xs + 2),
            _Row(
              label: 'Total',
              value:
                  '${Formatters.compactCurrency(fill.costQuote)} ${fill.quoteSymbol}',
              emphasize: true,
            ),
            SizedBox(height: t.spacing.xs + 2),
            _Row(
              label: 'Side',
              value: isBuy ? 'Buy' : 'Sell',
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(
          label,
          style: t.typography.bodySm.copyWith(
            color: t.colors.contentTertiary,
          ),
        ),
        Text(
          value,
          // Right-aligned values in this row are prices and
          // quantities — render them mono so the dialog's value
          // column doesn't reflow when a fill summary updates.
          style: t.typography.numericSm.copyWith(
            fontSize: 14,
            color: t.colors.contentPrimary,
            fontWeight: emphasize ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
