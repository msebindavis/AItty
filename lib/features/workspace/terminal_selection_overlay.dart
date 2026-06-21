import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../core/theme/obsidian_colors.dart';

class TerminalSelectionOverlay extends StatefulWidget {
  /// Size of each selection handle's tap target, in logical pixels.
  /// The painted balloon is [handleVisualSize] and is centered horizontally
  /// inside this square — the rest is transparent but still receives
  /// pan gestures so users with thicker fingers can grab a handle.
  static const double handleTapSize = 40;

  /// Visible balloon shape painted inside the [handleTapSize] tap target.
  static const Size handleVisualSize = Size(20, 26);

  /// Edge length of the floating Copy button. Larger than the handle's
  /// visual balloon so the tappable label icon reads as a deliberate
  /// action, not another handle.
  static const double copyButtonSize = 44;

  const TerminalSelectionOverlay({
    super.key,
    required this.terminalViewKey,
    required this.controller,
    required this.child,
    required this.onDragStart,
    required this.onDragEnd,
    required this.onCopy,
  });

  final GlobalKey<TerminalViewState> terminalViewKey;
  final TerminalController controller;
  final Widget child;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;
  final VoidCallback onCopy;

  @override
  State<TerminalSelectionOverlay> createState() => _TerminalSelectionOverlayState();
}

class _TerminalSelectionOverlayState extends State<TerminalSelectionOverlay> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onSelectionChanged);
  }

  @override
  void didUpdateWidget(covariant TerminalSelectionOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onSelectionChanged);
      widget.controller.addListener(_onSelectionChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onSelectionChanged);
    super.dispose();
  }

  void _onSelectionChanged() {
    if (mounted) setState(() {});
  }

  void _updateSelection(Offset localPosition, {required bool isStartHandle}) {
    final viewState = widget.terminalViewKey.currentState;
    if (viewState == null) return;

    final selection = widget.controller.selection;
    if (selection == null) return;

    final terminal = viewState.widget.terminal;

    // Convert touch offset to CellOffset
    // We adjust localPosition slightly because the handle is below the character
    final adjustedPosition = Offset(localPosition.dx, localPosition.dy - viewState.renderTerminal.cellSize.height);
    final targetOffset = viewState.renderTerminal.getCellOffset(adjustedPosition);

    if (isStartHandle) {
      // Don't let start cross end
      final endOffset = selection.end;
      if (targetOffset.y > endOffset.y || (targetOffset.y == endOffset.y && targetOffset.x > endOffset.x)) {
        return;
      }
      widget.controller.setSelection(
        terminal.buffer.createAnchorFromOffset(targetOffset),
        terminal.buffer.createAnchorFromOffset(endOffset),
      );
    } else {
      // Don't let end cross start
      final startOffset = selection.begin;
      if (targetOffset.y < startOffset.y || (targetOffset.y == startOffset.y && targetOffset.x < startOffset.x)) {
        return;
      }
      widget.controller.setSelection(
        terminal.buffer.createAnchorFromOffset(startOffset),
        terminal.buffer.createAnchorFromOffset(targetOffset),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final selection = widget.controller.selection;
    final viewState = widget.terminalViewKey.currentState;

    if (selection == null || viewState == null) {
      return widget.child;
    }
    final startOffset = selection.begin;
    final endOffset = selection.end;

    final startPixel = viewState.renderTerminal.getOffset(startOffset);
    final endPixel = viewState.renderTerminal.getOffset(endOffset);

    // Xterm getOffset gives the top-left of the cell.
    // We want the handle to be at the bottom of the cell.
    final cellSize = viewState.renderTerminal.cellSize;
    final handleOffset = TerminalSelectionOverlay.handleTapSize / 2;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Copy button floats just above the end handle so it sits next
        // to the user's finger after they release. If that position
        // would clip off the top of the terminal (selection is on the
        // first visible row), drop the button BELOW the end handle
        // instead.
        final aboveHandleTop = endPixel.dy + cellSize.height -
            TerminalSelectionOverlay.copyButtonSize -
            4;
        final belowHandleTop = endPixel.dy + cellSize.height +
            TerminalSelectionOverlay.handleTapSize +
            8;
        final copyTop = aboveHandleTop >= 0 ? aboveHandleTop : belowHandleTop;

        // Right-align with the end handle so the button "points" to the
        // selection's far edge. Clamp into the terminal so it never
        // disappears off the right edge on narrow phones.
        final rawCopyLeft =
            endPixel.dx + cellSize.width - TerminalSelectionOverlay.copyButtonSize;
        final copyLeft = rawCopyLeft.clamp(
          8.0,
          constraints.maxWidth - TerminalSelectionOverlay.copyButtonSize - 8.0,
        );

        return Stack(
          children: [
            widget.child,
            // Start Handle
            Positioned(
              left: startPixel.dx - handleOffset,
              top: startPixel.dy + cellSize.height,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => widget.onDragStart(),
                onPanEnd: (_) => widget.onDragEnd(),
                onPanCancel: widget.onDragEnd,
                onPanUpdate: (details) {
                  final box = context.findRenderObject() as RenderBox?;
                  if (box != null) {
                    final localPosition = box.globalToLocal(details.globalPosition);
                    _updateSelection(localPosition, isStartHandle: true);
                  }
                },
                child: const _SelectionHandle(isStart: true),
              ),
            ),
            // End Handle
            Positioned(
              left: endPixel.dx + cellSize.width - handleOffset,
              top: endPixel.dy + cellSize.height,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (_) => widget.onDragStart(),
                onPanEnd: (_) => widget.onDragEnd(),
                onPanCancel: widget.onDragEnd,
                onPanUpdate: (details) {
                  final box = context.findRenderObject() as RenderBox?;
                  if (box != null) {
                    final localPosition = box.globalToLocal(details.globalPosition);
                    _updateSelection(localPosition, isStartHandle: false);
                  }
                },
                child: const _SelectionHandle(isStart: false),
              ),
            ),
            // Copy button — placed inside the overlay (not the screen
            // corner) so it tracks the selection. Sits right above the
            // end handle, near where the user's thumb lands.
            Positioned(
              left: copyLeft,
              top: copyTop,
              child: _CopyButton(
                size: TerminalSelectionOverlay.copyButtonSize,
                onTap: widget.onCopy,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SelectionHandle extends StatelessWidget {
  final bool isStart;

  const _SelectionHandle({required this.isStart});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: TerminalSelectionOverlay.handleTapSize,
      height: TerminalSelectionOverlay.handleTapSize,
      // Center the painted balloon horizontally inside the larger tap
      // target. The vertical offset below comes from the Positioned
      // `top` in the parent — handle hangs off the bottom of the cell.
      alignment: Alignment.topCenter,
      child: CustomPaint(
        size: TerminalSelectionOverlay.handleVisualSize,
        painter: _HandlePainter(color: ObsidianColors.primary, isStart: isStart),
      ),
    );
  }
}

class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.size, required this.onTap});

  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(size / 2),
      color: ObsidianColors.primary,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(size / 2),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            Icons.content_copy,
            size: 22,
            color: ObsidianColors.onPrimary,
          ),
        ),
      ),
    );
  }
}

class _HandlePainter extends CustomPainter {
  final Color color;
  final bool isStart;

  _HandlePainter({required this.color, required this.isStart});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    if (isStart) {
      path.moveTo(size.width, 0);
      path.lineTo(size.width, size.height - size.width / 2);
      path.arcToPoint(
        Offset(0, size.height - size.width / 2),
        radius: Radius.circular(size.width / 2),
        clockwise: false,
      );
      path.lineTo(0, size.width / 2);
      path.arcToPoint(
        Offset(size.width, 0),
        radius: Radius.circular(size.width / 2),
        clockwise: true,
      );
    } else {
      path.moveTo(0, 0);
      path.lineTo(0, size.height - size.width / 2);
      path.arcToPoint(
        Offset(size.width, size.height - size.width / 2),
        radius: Radius.circular(size.width / 2),
        clockwise: true,
      );
      path.lineTo(size.width, size.width / 2);
      path.arcToPoint(
        Offset(0, 0),
        radius: Radius.circular(size.width / 2),
        clockwise: false,
      );
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HandlePainter oldDelegate) {
    return color != oldDelegate.color || isStart != oldDelegate.isStart;
  }
}
