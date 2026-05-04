import 'package:flutter/material.dart';

import '../../../design_system/lumina_ui.dart';
import 'backfill_button.dart';
import 'debug_event_drop_button.dart';
import 'debug_pause_control.dart';
import 'debug_price_offset_controls.dart';
import 'debug_speed_controls.dart';
import 'extend_history_button.dart';
import 'volume_overlay_toggle_button.dart';

/// Speed-dial-style aggregator for every debug FAB the chart needs.
/// Collapses to a single trigger FAB; tapping it fans the existing
/// controls out vertically with a staggered slide+fade animation. No
/// backdrop scrim — debug actions are inherently multi-tap (speed, price
/// offset) and a scrim would force re-opening the panel between every
/// adjustment.
class DebugPanel extends StatefulWidget {
  const DebugPanel({super.key});

  @override
  State<DebugPanel> createState() => _DebugPanelState();
}

class _DebugPanelState extends State<DebugPanel>
    with SingleTickerProviderStateMixin {
  static const Duration _expandDuration = Duration(milliseconds: 250);
  static const Duration _collapseDuration = Duration(milliseconds: 150);
  static const double _rowSpacing = 12.0;

  late final AnimationController _ctrl;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: _expandDuration,
      reverseDuration: _collapseDuration,
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded) {
        _ctrl.forward();
      } else {
        _ctrl.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Order matters: the topmost child is the last to animate in
    // (deepest stagger) so the fan-out reads upward from the trigger.
    const List<Widget> children = <Widget>[
      DebugEventDropButton(),
      VolumeOverlayToggleButton(),
      ExtendHistoryButton(),
      BackfillButton(),
      DebugPauseControl(),
      DebugPriceOffsetControls(),
      DebugSpeedControls(),
    ];

    final int n = children.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        // Custom collapse animation: ClipRect + Align with
        // `widthFactor: 1.0` so the wrapper hugs the inner column's
        // intrinsic width (rather than expanding to the full Scaffold
        // width like the default `SizeTransition` would), and
        // `alignment: Alignment.bottomRight` so the wide debug rows
        // stay right-aligned with the trigger FAB and shrink toward
        // it on collapse.
        AnimatedBuilder(
          animation: _ctrl,
          builder: (BuildContext context, Widget? child) {
            return ClipRect(
              child: Align(
                alignment: Alignment.bottomRight,
                widthFactor: 1.0,
                heightFactor: _ctrl.value.clamp(0.0, 1.0),
                child: child,
              ),
            );
          },
          child: IgnorePointer(
            ignoring: !_expanded,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                for (int i = 0; i < n; i++) ...<Widget>[
                  _StaggeredEntry(
                    controller: _ctrl,
                    // Index 0 (topmost) gets the longest stagger;
                    // bottommost (just above the trigger) appears first.
                    stagger: (n - 1 - i) / n,
                    child: children[i],
                  ),
                  const SizedBox(height: _rowSpacing),
                ],
              ],
            ),
          ),
        ),
        _TriggerFab(expanded: _expanded, onPressed: _toggle),
      ],
    );
  }
}

class _StaggeredEntry extends StatelessWidget {
  const _StaggeredEntry({
    required this.controller,
    required this.stagger,
    required this.child,
  });

  final AnimationController controller;

  /// 0..1 — how far into the parent timeline this child becomes visible.
  final double stagger;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final CurvedAnimation curve = CurvedAnimation(
      parent: controller,
      curve: Interval(stagger * 0.6, 1.0, curve: Curves.easeOutCubic),
      reverseCurve: Interval(0.0, 1.0 - stagger * 0.4, curve: Curves.easeIn),
    );
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.4),
          end: Offset.zero,
        ).animate(curve),
        child: child,
      ),
    );
  }
}

class _TriggerFab extends StatelessWidget {
  const _TriggerFab({required this.expanded, required this.onPressed});

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final LuminaTokens t = context.tokens;
    return FloatingActionButton(
      heroTag: 'debug-panel-trigger',
      tooltip: expanded ? 'Hide debug tools' : 'Show debug tools',
      backgroundColor: expanded
          ? t.colors.feedbackNegativeSurface
          : t.colors.accentPrimary,
      foregroundColor: expanded
          ? t.colors.feedbackNegative
          : t.colors.onAccentPrimary,
      onPressed: onPressed,
      child: AnimatedRotation(
        turns: expanded ? 0.125 : 0.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: Icon(expanded ? Icons.close : Icons.bug_report),
      ),
    );
  }
}
