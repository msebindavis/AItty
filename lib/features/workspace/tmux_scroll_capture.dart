import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../utils/terminal_input.dart';

/// Transparent layer over the terminal that captures finger swipes in tmux
/// scroll mode and forwards them as line up/down keys, paced to finger movement.
class TmuxScrollCapture extends StatefulWidget {
  const TmuxScrollCapture({
    super.key,
    required this.onScrollLine,
    this.pixelsPerLine = 14,
  });

  final void Function({required bool up}) onScrollLine;
  final double pixelsPerLine;

  @override
  State<TmuxScrollCapture> createState() => _TmuxScrollCaptureState();
}

class _TmuxScrollCaptureState extends State<TmuxScrollCapture> {
  var _accumulatedDelta = 0.0;
  var _tracking = false;

  void _scrollLine(bool up) {
    widget.onScrollLine(up: up);
  }

  void _applyDelta(double dy) {
    if (dy == 0) return;
    _accumulatedDelta += dy;
    final step = widget.pixelsPerLine;
    while (_accumulatedDelta >= step) {
      _accumulatedDelta -= step;
      _scrollLine(true);
    }
    while (_accumulatedDelta <= -step) {
      _accumulatedDelta += step;
      _scrollLine(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) {
        _tracking = true;
      },
      onPointerMove: (event) {
        if (!_tracking) return;
        _applyDelta(event.delta.dy);
      },
      onPointerUp: (_) {
        _tracking = false;
        _accumulatedDelta = 0;
      },
      onPointerCancel: (_) {
        _tracking = false;
        _accumulatedDelta = 0;
      },
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          _applyDelta(event.scrollDelta.dy);
        }
      },
      child: const ColoredBox(color: Color(0x00000000)),
    );
  }
}

void dispatchTmuxScrollLine(void Function(Uint8List bytes) send, {required bool up}) {
  send(up ? TerminalInput.arrowUp() : TerminalInput.arrowDown());
}

/// Finger pixels required per output line — lower = more sensitive.
double tmuxScrollPixelsPerLine(BuildContext context) {
  final fontSize = Theme.of(context).textTheme.bodyMedium?.fontSize ?? 14;
  return fontSize * MediaQuery.textScalerOf(context).scale(1) * 1.0;
}
