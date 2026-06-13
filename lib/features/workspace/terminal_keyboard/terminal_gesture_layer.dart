import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../utils/terminal_input.dart';

/// Termius-style terminal gestures: long-press drag arrows, double-tap tab, pinch zoom.
class TerminalGestureLayer extends StatefulWidget {
  const TerminalGestureLayer({
    super.key,
    required this.child,
    required this.enabled,
    required this.onArrow,
    required this.onTab,
    required this.onFontScaleChanged,
    required this.fontScale,
  });

  final Widget child;
  final bool enabled;
  final ValueChanged<TerminalArrowDirection> onArrow;
  final VoidCallback onTab;
  final ValueChanged<double> onFontScaleChanged;
  final double fontScale;

  @override
  State<TerminalGestureLayer> createState() => _TerminalGestureLayerState();
}

class _TerminalGestureLayerState extends State<TerminalGestureLayer> {
  Timer? _repeatTimer;
  Offset? _dragOrigin;
  TerminalArrowDirection? _dragDirection;
  int _speedGear = 0;
  double _basePinchScale = 1;

  @override
  void dispose() {
    _stopRepeat();
    super.dispose();
  }

  void _stopRepeat() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  void _startRepeat(TerminalArrowDirection direction) {
    if (_dragDirection == direction && _repeatTimer != null) return;
    _dragDirection = direction;
    _stopRepeat();
    widget.onArrow(direction);
    _repeatTimer = Timer.periodic(_intervalForGear(_speedGear), (_) => widget.onArrow(direction));
  }

  Duration _intervalForGear(int gear) => switch (gear) {
        0 => const Duration(milliseconds: 180),
        1 => const Duration(milliseconds: 90),
        _ => const Duration(milliseconds: 45),
      };

  void _updateDrag(Offset localPosition) {
    final origin = _dragOrigin;
    if (origin == null) return;
    final delta = localPosition - origin;
    if (delta.distance < 16) return;

    final angle = math.atan2(delta.dy, delta.dx);
    final direction = _directionFromAngle(angle);
    if (direction == null) return;

    final gear = delta.distance < 48
        ? 0
        : delta.distance < 120
            ? 1
            : 2;
    if (gear != _speedGear) {
      _speedGear = gear;
      if (_dragDirection == direction) {
        _startRepeat(direction);
      }
    }
    _startRepeat(direction);
  }

  TerminalArrowDirection? _directionFromAngle(double radians) {
    final deg = (radians * 180 / math.pi + 360) % 360;
    if (deg >= 315 || deg < 45) return TerminalArrowDirection.right;
    if (deg >= 45 && deg < 135) return TerminalArrowDirection.down;
    if (deg >= 135 && deg < 225) return TerminalArrowDirection.left;
    return TerminalArrowDirection.up;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTap: widget.onTab,
      onLongPressStart: (details) {
        _dragOrigin = details.localPosition;
        _speedGear = 0;
        _dragDirection = null;
      },
      onLongPressMoveUpdate: (details) => _updateDrag(details.localPosition),
      onLongPressEnd: (_) {
        _dragOrigin = null;
        _dragDirection = null;
        _speedGear = 0;
        _stopRepeat();
      },
      onLongPressCancel: () {
        _dragOrigin = null;
        _dragDirection = null;
        _speedGear = 0;
        _stopRepeat();
      },
      onScaleStart: (details) {
        _basePinchScale = widget.fontScale;
      },
      onScaleUpdate: (details) {
        if (details.pointerCount < 2) return;
        final next = (_basePinchScale * details.scale).clamp(0.75, 2.0);
        widget.onFontScaleChanged(next);
      },
      child: widget.child,
    );
  }
}
