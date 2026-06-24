import 'package:flutter/material.dart';

import '../../../core/theme/obsidian_colors.dart';
import '../../../utils/terminal_input.dart';

/// Floating arrow-pad bubble with a center Enter button.
///
/// The widget is rendered inside a host-owned [OverlayPortal]. The host
/// (typically [WorkspaceScreen]) owns the [OverlayPortalController] and
/// toggles it when the toolbar's arrows icon is tapped. The host also
/// positions the [OverlayPortal] so the bubble sits above the arrows
/// button.
///
/// Layout (d-pad shape):
///
/// ```
///   ┌────────┬────────┬────────┐
///   │        │   ↑    │        │
///   ├────────┼────────┼────────┤
///   │   ←    │   ↵    │   →    │
///   ├────────┼────────┼────────┤
///   │        │   ↓    │        │
///   └────────┴────────┴────────┘
/// ```
///
/// Arrows route through [onArrow] so the host can honour sticky
/// Ctrl/Alt modifier combinations. The Enter button calls [onEnter]
/// (host sends a literal `\r`).
class ArrowPad extends StatelessWidget {
  const ArrowPad({
    super.key,
    required this.controller,
    required this.onArrow,
    required this.onEnter,
  });

  /// Controller that the host uses to show/hide this widget. Kept as
  /// a prop (rather than a field) so a single controller can drive
  /// multiple portals and so tests can swap it.
  final OverlayPortalController controller;

  /// Called when an arrow key is tapped.
  final ValueChanged<TerminalArrowDirection> onArrow;

  /// Called when the center Enter button is tapped.
  final VoidCallback onEnter;

  /// Width of one cell in the d-pad grid.
  static const double cellWidth = 56.0;

  /// Height of one cell in the d-pad grid.
  static const double cellHeight = 48.0;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        // 3 cells × [cellWidth] + 4 px padding on each side. The hardcoded
        // width makes the d-pad shape predictable; the parent [Positioned]
        // is responsible for keeping the bubble on-screen.
        width: cellWidth * 3 + 8,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: ObsidianColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: ObsidianColors.outlineVariant.withValues(alpha: 0.4),
            width: 0.5,
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Row 1: empty / ↑ / empty. [Expanded] cells share the row's
            // width equally, so any 1-px rounding from the outer
            // [Container] / [Row] layout is absorbed by Expanded's
            // slack — no RenderFlex overflow.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Expanded(child: _SpacerCell()),
                Expanded(
                  child: _ArrowCell(
                    icon: Icons.keyboard_arrow_up,
                    onTap: () => onArrow(TerminalArrowDirection.up),
                  ),
                ),
                const Expanded(child: _SpacerCell()),
              ],
            ),
            // Row 2: ← / ↵ / →
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: _ArrowCell(
                    icon: Icons.keyboard_arrow_left,
                    onTap: () => onArrow(TerminalArrowDirection.left),
                  ),
                ),
                Expanded(
                  child: _EnterCell(onTap: onEnter),
                ),
                Expanded(
                  child: _ArrowCell(
                    icon: Icons.keyboard_arrow_right,
                    onTap: () => onArrow(TerminalArrowDirection.right),
                  ),
                ),
              ],
            ),
            // Row 3: empty / ↓ / empty
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Expanded(child: _SpacerCell()),
                Expanded(
                  child: _ArrowCell(
                    icon: Icons.keyboard_arrow_down,
                    onTap: () => onArrow(TerminalArrowDirection.down),
                  ),
                ),
                const Expanded(child: _SpacerCell()),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ArrowCell extends StatelessWidget {
  const _ArrowCell({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PadKey(
      onTap: onTap,
      child: Icon(icon, size: 20, color: ObsidianColors.onSurface),
    );
  }
}

class _EnterCell extends StatelessWidget {
  const _EnterCell({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _PadKey(
      onTap: onTap,
      child: const Text(
        '↵',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: ObsidianColors.onSurface,
        ),
      ),
    );
  }
}

class _SpacerCell extends StatelessWidget {
  const _SpacerCell();

  @override
  Widget build(BuildContext context) {
    // Width comes from the parent [Expanded]; only the height is fixed.
    return const SizedBox(height: ArrowPad.cellHeight);
  }
}

class _PadKey extends StatelessWidget {
  const _PadKey({required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // ClipRRect prevents the Material's ink splash from leaking past the
    // rounded corners and into the adjacent cell — without it, an InkWell
    // ripple can paint 1 px into the neighbour, which the parent Row then
    // reports as a 1-px RenderFlex overflow. Width is supplied by the
    // parent's [Expanded]; only the height is fixed here.
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: ArrowPad.cellHeight,
        child: Material(
          color: ObsidianColors.surfaceContainerHighest,
          child: InkWell(
            onTap: onTap,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
