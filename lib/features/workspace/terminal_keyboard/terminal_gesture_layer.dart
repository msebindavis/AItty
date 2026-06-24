import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../utils/terminal_input.dart';
import '../pinch_zoom_policy.dart';

/// Termius-style terminal gestures: long-press drag arrows, double-tap tab, pinch zoom.
///
/// The pinch recognizer shares the same GestureDetector as long-press / pan, so
/// it can win the arena mid-gesture when a second finger lands. We resolve the
/// conflict with a single rule: **only one recognizer fires per gesture.**
/// - While [_pinching] is true, single-finger long-press moves are ignored.
/// - When a 2-finger scale starts, any in-flight long-press drag is cancelled
///   (origin cleared, repeat timer stopped) so arrow keys don't keep firing
///   under the user's fingers while they pinch.
///
/// [absorbTaps] true means tap-up events are swallowed by this layer instead of
/// bubbling to xterm's `TerminalGestureHandler` (which would otherwise call
/// `_focusNode.requestFocus()` and open the IME on Android). Tap-down still
/// clears an active selection — that matches xterm's own tap behaviour and is
/// the only legitimate "tap on terminal" action we want to support here. tmux
/// panes pass `absorbTaps: false` so xterm's full tap-to-focus flow remains
/// in effect; plain shells pass `absorbTaps: true`.
class TerminalGestureLayer extends StatefulWidget {
  const TerminalGestureLayer({
    super.key,
    required this.child,
    required this.enabled,
    required this.onArrow,
    required this.onTab,
    required this.onFontScaleChanged,
    required this.fontScale,
    this.onSelectWord,
    this.onClearSelection,
    this.absorbTaps = false,
  });

  final Widget child;
  final bool enabled;
  final ValueChanged<TerminalArrowDirection> onArrow;
  final VoidCallback onTab;
  final ValueChanged<double> onFontScaleChanged;
  final double fontScale;
  final void Function(Offset)? onSelectWord;
  final VoidCallback? onClearSelection;

  /// When true, taps are absorbed by this layer (xterm's tap handler is
  /// suppressed, so focus requests and the IME never open from a tap).
  /// Active selections are still cleared on tap, mimicking xterm's own
  /// tap-to-dismiss behaviour.
  final bool absorbTaps;

  @override
  State<TerminalGestureLayer> createState() => _TerminalGestureLayerState();
}

class _TerminalGestureLayerState extends State<TerminalGestureLayer> {
  Timer? _repeatTimer;
  Offset? _dragOrigin;
  TerminalArrowDirection? _dragDirection;
  int _speedGear = 0;
  double _basePinchScale = 1;
  bool _pinching = false;

  @override
  void dispose() {
    _stopRepeat();
    super.dispose();
  }

  void _stopRepeat() {
    _repeatTimer?.cancel();
    _repeatTimer = null;
  }

  void _cancelDrag() {
    _dragOrigin = null;
    _dragDirection = null;
    _speedGear = 0;
    _stopRepeat();
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

    if (_dragDirection == null) {
      widget.onClearSelection?.call();
    }

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
      // Translucent lets children see the same pointer events so xterm's
      // long-press / scale recognizers still work. For taps, both this
      // detector and xterm's TerminalGestureDetector will accept on the
      // same pointer-up; the gesture arena gives the tie to the first
      // (outer) detector, which is us when absorbTaps is true — so the
      // tap is captured here and never reaches xterm's
      // _focusNode.requestFocus() call.
      behavior: HitTestBehavior.translucent,
      onTap: widget.absorbTaps
          ? () {
              // Preserve xterm's "tap on selected text clears it" behaviour.
              widget.onClearSelection?.call();
              // xterm's onTapDown runs before us (tap-down fires
              // forceCallback: true) and calls _focusNode.requestFocus().
              // On Android that opens the IME via the system input
              // channel even when hardwareKeyboardOnly=true. Dismiss it
              // immediately so the tap is invisible to the keyboard,
              // while leaving the terminal's focus node intact so a
              // physical keyboard still types into the shell.
              SystemChannels.textInput.invokeMethod('TextInput.hide');
            }
          : null,
      onDoubleTap: widget.onTab,
      onLongPressStart: (details) {
        _dragOrigin = details.localPosition;
        _speedGear = 0;
        _dragDirection = null;
        widget.onSelectWord?.call(details.localPosition);
      },
      onLongPressMoveUpdate: (details) {
        // Arena guard: if a pinch has been claimed, ignore the 1-finger drag.
        if (_pinching) return;
        _updateDrag(details.localPosition);
      },
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
        if (details.pointerCount < 2) return;
        // A second finger landed: claim the gesture for pinch and cancel
        // any in-flight long-press so the arrow-repeat doesn't keep firing.
        // Also drop any active selection — if the user long-pressed with one
        // finger (creating the selection) and then added a second to pinch,
        // the selection is no longer what they want.
        _pinching = true;
        _basePinchScale = widget.fontScale;
        _cancelDrag();
        widget.onClearSelection?.call();
      },
      onScaleUpdate: (details) {
        if (!_pinching) return;
        final next = PinchZoomPolicy.resolve(
          baseScale: _basePinchScale,
          gestureScale: details.scale,
        );
        if (next != widget.fontScale) {
          widget.onFontScaleChanged(next);
        }
      },
      onScaleEnd: (_) {
        _pinching = false;
      },
      child: widget.child,
    );
  }
}
