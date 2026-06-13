import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/obsidian_colors.dart';
import '../../utils/terminal_input.dart';

enum TmuxScrollStep { line, page }

void dispatchTmuxScroll(
  void Function(Uint8List bytes) send, {
  required bool up,
  TmuxScrollStep step = TmuxScrollStep.line,
}) {
  send(switch ((up, step)) {
    (true, TmuxScrollStep.line) => TerminalInput.arrowUp(),
    (false, TmuxScrollStep.line) => TerminalInput.arrowDown(),
    (true, TmuxScrollStep.page) => TerminalInput.pageUp(),
    (false, TmuxScrollStep.page) => TerminalInput.pageDown(),
  });
}

/// Compact floating scroll control for tmux pane history on mobile.
class TmuxSideScrollRail extends StatefulWidget {
  const TmuxSideScrollRail({
    super.key,
    required this.copyModeActive,
    required this.onPrepareScroll,
    required this.onExitCopyMode,
    required this.onScroll,
  });

  final bool copyModeActive;
  final Future<void> Function() onPrepareScroll;
  final VoidCallback onExitCopyMode;
  final void Function({required bool up, TmuxScrollStep step}) onScroll;

  @override
  State<TmuxSideScrollRail> createState() => _TmuxSideScrollRailState();
}

class _TmuxSideScrollRailState extends State<TmuxSideScrollRail> {
  Timer? _repeatTimer;
  var _accumulatedDelta = 0.0;
  Future<void>? _prepareFuture;
  var _preparedThisGesture = false;

  @override
  void dispose() {
    _stopRepeat();
    super.dispose();
  }

  Future<void> _ensurePrepared() async {
    if (_preparedThisGesture) return;
    _prepareFuture ??= widget.onPrepareScroll();
    await _prepareFuture;
    _preparedThisGesture = true;
  }

  void _resetGesture() {
    _stopRepeat();
    _accumulatedDelta = 0;
    _prepareFuture = null;
    _preparedThisGesture = false;
  }

  void _stopRepeat() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  void _beginRepeat({required bool up, TmuxScrollStep step = TmuxScrollStep.page}) {
    _stopRepeat();
    unawaited(_ensurePrepared().then((_) {
      if (!mounted) return;
      widget.onScroll(up: up, step: step);
      HapticFeedback.selectionClick();
      _repeatTimer = Timer.periodic(const Duration(milliseconds: 55), (_) {
        widget.onScroll(up: up, step: step);
      });
    }));
  }

  void _applyDragDelta(double dy) {
    if (dy == 0) return;
    unawaited(_ensurePrepared().then((_) {
      if (!mounted || !_preparedThisGesture) return;
      _accumulatedDelta += dy;
      const pixelsPerLine = 12.0;
      while (_accumulatedDelta >= pixelsPerLine) {
        _accumulatedDelta -= pixelsPerLine;
        widget.onScroll(up: true, step: TmuxScrollStep.line);
      }
      while (_accumulatedDelta <= -pixelsPerLine) {
        _accumulatedDelta += pixelsPerLine;
        widget.onScroll(up: false, step: TmuxScrollStep.line);
      }
    }));
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Scroll terminal history',
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          width: 36,
          decoration: BoxDecoration(
            color: ObsidianColors.surfaceContainerHigh.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: ObsidianColors.outlineVariant.withValues(alpha: 0.45)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _RailButton(
                icon: Icons.expand_less,
                semanticsLabel: 'Scroll up',
                onPointerDown: () => _beginRepeat(up: true),
                onPointerUp: _resetGesture,
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (_) {
                  _resetGesture();
                  unawaited(_ensurePrepared());
                },
                onVerticalDragUpdate: (details) => _applyDragDelta(details.delta.dy),
                onVerticalDragEnd: (_) => _resetGesture(),
                onVerticalDragCancel: _resetGesture,
                child: Container(
                  width: 36,
                  height: 28,
                  alignment: Alignment.center,
                  child: Container(
                    width: 3,
                    height: 20,
                    decoration: BoxDecoration(
                      color: ObsidianColors.outline.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              _RailButton(
                icon: Icons.expand_more,
                semanticsLabel: 'Scroll down',
                onPointerDown: () => _beginRepeat(up: false),
                onPointerUp: _resetGesture,
              ),
              if (widget.copyModeActive)
                _RailButton(
                  icon: Icons.circle,
                  iconSize: 10,
                  semanticsLabel: 'Return to live',
                  tint: ObsidianColors.primary,
                  onPointerDown: () {
                    _resetGesture();
                    widget.onExitCopyMode();
                  },
                  onPointerUp: () {},
                )
              else
                const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.icon,
    required this.semanticsLabel,
    required this.onPointerDown,
    required this.onPointerUp,
    this.iconSize = 22,
    this.tint,
  });

  final IconData icon;
  final String semanticsLabel;
  final VoidCallback onPointerDown;
  final VoidCallback onPointerUp;
  final double iconSize;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => onPointerDown(),
        onPointerUp: (_) => onPointerUp(),
        onPointerCancel: (_) => onPointerUp(),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(
            icon,
            size: iconSize,
            color: tint ?? ObsidianColors.onSurface.withValues(alpha: 0.85),
          ),
        ),
      ),
    );
  }
}
