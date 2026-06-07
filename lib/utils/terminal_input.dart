import 'dart:convert';
import 'dart:typed_data';

/// Builds bytes for terminal modifier / special keys.
abstract final class TerminalInput {
  static Uint8List esc() => Uint8List.fromList([0x1b]);

  static Uint8List tab() => Uint8List.fromList([0x09]);

  static Uint8List enter() => Uint8List.fromList([0x0d]);

  static Uint8List backspace() => Uint8List.fromList([0x7f]);

  static Uint8List arrowLeft() => Uint8List.fromList([0x1b, 0x5b, 0x44]);

  static Uint8List arrowRight() => Uint8List.fromList([0x1b, 0x5b, 0x43]);

  static Uint8List arrowUp() => Uint8List.fromList([0x1b, 0x5b, 0x41]);

  static Uint8List arrowDown() => Uint8List.fromList([0x1b, 0x5b, 0x42]);

  static Uint8List pageUp() => Uint8List.fromList([0x1b, 0x5b, 0x35, 0x7e]);

  static Uint8List pageDown() => Uint8List.fromList([0x1b, 0x5b, 0x36, 0x7e]);

  static Uint8List ctrl(String char) {
    final code = char.toLowerCase().codeUnitAt(0);
    if (code < 0x61 || code > 0x7a) return utf8.encode(char);
    return Uint8List.fromList([code - 0x60]);
  }

  static Uint8List alt(String char) => Uint8List.fromList([0x1b, ...utf8.encode(char)]);

  static Uint8List text(String text) => Uint8List.fromList(utf8.encode(text));

  static Uint8List commandLine(String command) => text('$command\n');

  /// Default tmux prefix (Ctrl+b) then `[` — enters copy/scroll mode.
  static Uint8List tmuxCopyModeEnter() => Uint8List.fromList([0x02, 0x5b]);

  /// Exits tmux copy mode.
  static Uint8List tmuxCopyModeExit() => text('q');
}
