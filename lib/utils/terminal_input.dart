import 'dart:convert';
import 'dart:typed_data';

/// Builds bytes for terminal modifier / special keys.
abstract final class TerminalInput {
  static Uint8List esc() => Uint8List.fromList([0x1b]);

  static Uint8List tab() => Uint8List.fromList([0x09]);

  /// CSI Z — reverse tab / shift-tab (xterm).
  static Uint8List shiftTab() => Uint8List.fromList([0x1b, 0x5b, 0x5a]);

  static Uint8List enter() => Uint8List.fromList([0x0d]);

  static Uint8List backspace() => Uint8List.fromList([0x7f]);

  static Uint8List arrowLeft() => Uint8List.fromList([0x1b, 0x5b, 0x44]);

  static Uint8List arrowRight() => Uint8List.fromList([0x1b, 0x5b, 0x43]);

  static Uint8List arrowUp() => Uint8List.fromList([0x1b, 0x5b, 0x41]);

  static Uint8List arrowDown() => Uint8List.fromList([0x1b, 0x5b, 0x42]);

  static Uint8List pageUp() => Uint8List.fromList([0x1b, 0x5b, 0x35, 0x7e]);

  static Uint8List pageDown() => Uint8List.fromList([0x1b, 0x5b, 0x36, 0x7e]);

  static Uint8List home() => Uint8List.fromList([0x1b, 0x5b, 0x48]);

  static Uint8List end() => Uint8List.fromList([0x1b, 0x5b, 0x46]);

  static Uint8List insert() => Uint8List.fromList([0x1b, 0x5b, 0x32, 0x7e]);

  static Uint8List deleteForward() => Uint8List.fromList([0x1b, 0x5b, 0x33, 0x7e]);

  /// SS3 / CSI function keys (F1–F12, xterm).
  static Uint8List functionKey(int n) {
    if (n < 1 || n > 12) {
      throw ArgumentError.value(n, 'n', 'must be between 1 and 12');
    }
    if (n <= 4) {
      return Uint8List.fromList([0x1b, 0x4f, 0x50 + (n - 1)]);
    }
    final code = n + 10;
    return Uint8List.fromList([0x1b, 0x5b, ...utf8.encode('$code'), 0x7e]);
  }

  static Uint8List symbol(String char) => text(char);

  /// CSI 1 ; modifier D/C/A/B — xterm-style modified arrows.
  static Uint8List modifiedArrow({
    required TerminalArrowDirection direction,
    int modifier = 1,
  }) {
    final code = switch (direction) {
      TerminalArrowDirection.left => 0x44,
      TerminalArrowDirection.right => 0x43,
      TerminalArrowDirection.up => 0x41,
      TerminalArrowDirection.down => 0x42,
    };
    return Uint8List.fromList([
      0x1b,
      0x5b,
      0x31,
      0x3b,
      ...utf8.encode('$modifier'),
      code,
    ]);
  }

  static Uint8List ctrlArrow(TerminalArrowDirection direction) =>
      modifiedArrow(direction: direction, modifier: 5);

  static Uint8List altArrow(TerminalArrowDirection direction) =>
      modifiedArrow(direction: direction, modifier: 3);

  static Uint8List arrow(TerminalArrowDirection direction) => switch (direction) {
        TerminalArrowDirection.left => arrowLeft(),
        TerminalArrowDirection.right => arrowRight(),
        TerminalArrowDirection.up => arrowUp(),
        TerminalArrowDirection.down => arrowDown(),
      };

  static Uint8List ctrl(String char) {
    final code = char.toLowerCase().codeUnitAt(0);
    if (code < 0x61 || code > 0x7a) return utf8.encode(char);
    return Uint8List.fromList([code - 0x60]);
  }

  static Uint8List alt(String char) => Uint8List.fromList([0x1b, ...utf8.encode(char)]);

  static Uint8List text(String text) => Uint8List.fromList(utf8.encode(text));

  static Uint8List commandLine(String command) => text('$command\n');
}

enum TerminalArrowDirection { left, right, up, down }
