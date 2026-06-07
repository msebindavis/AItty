import 'dart:io';

import 'package:flutter/services.dart';

/// Keeps the Android process alive while SSH sessions are open.
///
/// Mobile OSes suspend background apps and close TCP sockets. A foreground
/// service (with a persistent notification) tells Android the connection is
/// active work that should not be killed.
class SessionForeground {
  static const _channel = MethodChannel('ai.aitty.app/foreground');

  static Future<void> start(int sessionCount) async {
    if (!Platform.isAndroid || sessionCount <= 0) return;
    try {
      await _channel.invokeMethod<void>('start', {'count': sessionCount});
    } on PlatformException {
      // Non-fatal: SSH still works in foreground without the service.
    }
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      // Ignore.
    }
  }
}
