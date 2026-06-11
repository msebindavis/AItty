import 'package:flutter/scheduler.dart';

/// Wait until overlay route animations (bottom sheets, dialogs) have finished.
Future<void> waitForRouteTransition({int frames = 2}) async {
  for (var i = 0; i < frames; i++) {
    await SchedulerBinding.instance.endOfFrame;
  }
}
