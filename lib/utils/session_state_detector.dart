import 'package:xterm/xterm.dart';

import '../models/session.dart';

abstract final class SessionStateDetector {
  static String lastLinePreview(Terminal terminal) {
    final buffer = terminal.buffer;
    if (buffer.height <= 0) return '';
    for (var y = buffer.height - 1; y >= 0; y--) {
      final text = buffer.lines[y].getText().trim();
      if (text.isNotEmpty) return text;
    }
    return buffer.lines[buffer.height - 1].getText().trim();
  }

  static SessionState detect(String preview, String latestChunk) {
    if (RegExp(r'\[Y/n\]|\[y/N\]|:\s*$').hasMatch(preview)) {
      return SessionState.awaitingInput;
    }
    if (latestChunk.contains('%') || latestChunk.contains('Epoch')) {
      return SessionState.processing;
    }
    if (preview.isEmpty) return SessionState.idle;
    return SessionState.connected;
  }
}
