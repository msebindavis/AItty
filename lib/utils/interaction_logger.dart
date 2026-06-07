import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Debug-only logging of the current screen and user taps to trace errors.
abstract final class InteractionLogger {
  static String? _currentRoute;
  static String? _lastClick;
  static DateTime? _lastClickAt;

  static String get currentRoute => _currentRoute ?? 'unknown';

  static void install() {
    if (!kDebugMode) return;

    final previousFlutterError = FlutterError.onError;
    FlutterError.onError = (details) {
      _logErrorBanner('FlutterError', details.exceptionAsString());
      previousFlutterError?.call(details);
    };

    final previousPlatformError = ui.PlatformDispatcher.instance.onError;
    ui.PlatformDispatcher.instance.onError = (error, stack) {
      _logErrorBanner('PlatformDispatcher', error.toString());
      return previousPlatformError?.call(error, stack) ?? false;
    };
  }

  static void logScreen(String route, {String? detail}) {
    if (!kDebugMode) return;
    _currentRoute = route;
    final suffix = detail != null && detail.isNotEmpty ? ' ($detail)' : '';
    debugPrint('[SCREEN] $route$suffix');
  }

  static void logClick({
    required Offset globalPosition,
    required int buttons,
    String? targetSummary,
  }) {
    if (!kDebugMode) return;
    final buttonLabel = _buttonLabel(buttons);
    final target = targetSummary != null && targetSummary.isNotEmpty ? ' → $targetSummary' : '';
    _lastClickAt = DateTime.now();
    _lastClick = '$buttonLabel @ (${globalPosition.dx.toStringAsFixed(1)}, ${globalPosition.dy.toStringAsFixed(1)})$target';
    debugPrint('[CLICK] $_lastClick on [$_currentRoute]');
  }

  static void logNavigation(String action, {String? detail}) {
    if (!kDebugMode) return;
    final suffix = detail != null && detail.isNotEmpty ? ': $detail' : '';
    debugPrint('[NAV] $action$suffix on [$_currentRoute]');
  }

  static void _logErrorBanner(String source, String message) {
    if (!kDebugMode) return;
    debugPrint('');
    debugPrint('══════════════════════════════════════════');
    debugPrint('[$source] $message');
    debugPrint('[CONTEXT] screen=$_currentRoute');
    if (_lastClick != null) {
      final ago = _lastClickAt != null ? DateTime.now().difference(_lastClickAt!).inMilliseconds : null;
      final timing = ago != null ? ' (${ago}ms ago)' : '';
      debugPrint('[CONTEXT] lastClick=$_lastClick$timing');
    } else {
      debugPrint('[CONTEXT] lastClick=(none recorded)');
    }
    debugPrint('══════════════════════════════════════════');
    debugPrint('');
  }

  static String _buttonLabel(int buttons) {
    if (buttons == kPrimaryButton) return 'tap';
    if (buttons == kSecondaryButton) return 'right-click';
    if (buttons == kMiddleMouseButton) return 'middle-click';
    return 'pointer($buttons)';
  }

  static String describeHitTest(HitTestResult result) {
    final parts = <String>[];
    for (final entry in result.path) {
      final type = entry.target.runtimeType.toString();
      if (type.startsWith('RenderSemantics') || type == 'RenderPointerListener') continue;
      parts.add(type);
      if (parts.length >= 5) break;
    }
    return parts.join(' → ');
  }
}

/// Captures pointer events app-wide and logs them with the active route.
class InteractionLogScope extends StatelessWidget {
  const InteractionLogScope({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return child;

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        final box = context.findRenderObject();
        final globalPosition = box is RenderBox ? box.localToGlobal(event.localPosition) : event.localPosition;
        final result = HitTestResult();
        final view = ui.PlatformDispatcher.instance.implicitView;
        if (view != null) {
          WidgetsBinding.instance.hitTestInView(result, globalPosition, view.viewId);
        }
        InteractionLogger.logClick(
          globalPosition: globalPosition,
          buttons: event.buttons,
          targetSummary: InteractionLogger.describeHitTest(result),
        );
      },
      child: child,
    );
  }
}
