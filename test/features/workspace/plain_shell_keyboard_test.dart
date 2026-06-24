import 'package:ai_tty/features/workspace/terminal_focus_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TerminalFocusPolicy (plain shell keyboard gating)', () {
    test('tmux pane, active, mobile, no toggle → autofocus on, hwkb-only on (IME off)', () {
      final p = TerminalFocusPolicy.resolve(
        isTmux: true,
        isActive: true,
        forceSoftKeyboard: false,
        mobile: true,
      );
      expect(p.autofocus, isTrue);
      expect(p.hardwareKeyboardOnly, isTrue,
          reason: 'tmux pane defaults to hwkb-only on mobile; toolbar keyboard icon opens IME');
    });

    test('tmux pane, active, mobile, toggle on → autofocus on, hwkb-only off', () {
      final p = TerminalFocusPolicy.resolve(
        isTmux: true,
        isActive: true,
        forceSoftKeyboard: true,
        mobile: true,
      );
      expect(p.autofocus, isTrue);
      expect(p.hardwareKeyboardOnly, isFalse);
    });

    test('tmux pane, active, desktop, no toggle → autofocus on, hwkb-only on', () {
      final p = TerminalFocusPolicy.resolve(
        isTmux: true,
        isActive: true,
        forceSoftKeyboard: false,
        mobile: false,
      );
      expect(p.autofocus, isTrue);
      expect(p.hardwareKeyboardOnly, isTrue);
    });

    test('tmux pane, inactive → autofocus off, hwkb-only on', () {
      final p = TerminalFocusPolicy.resolve(
        isTmux: true,
        isActive: false,
        forceSoftKeyboard: false,
        mobile: true,
      );
      expect(p.autofocus, isFalse);
      expect(p.hardwareKeyboardOnly, isTrue);
    });

    test('plain shell, active, mobile, no toggle → autofocus off, hwkb-only on', () {
      final p = TerminalFocusPolicy.resolve(
        isTmux: false,
        isActive: true,
        forceSoftKeyboard: false,
        mobile: true,
      );
      expect(p.autofocus, isFalse,
          reason: 'plain shell must not autofocus on tab activation');
      expect(p.hardwareKeyboardOnly, isTrue,
          reason: 'plain shell must never open the IME from a touch');
    });

    test('plain shell, active, mobile, toggle on → autofocus off, hwkb-only off', () {
      // Toolbar keyboard icon is the explicit IME entry point; it flips
      // hardwareKeyboardOnly off (IME allowed) and calls _focusTerminal
      // directly via requestFocus — autofocus prop is irrelevant on this path.
      final p = TerminalFocusPolicy.resolve(
        isTmux: false,
        isActive: true,
        forceSoftKeyboard: true,
        mobile: true,
      );
      expect(p.autofocus, isFalse,
          reason: 'autofocus stays off for plain shells; toolbar icon primes focus explicitly');
      expect(p.hardwareKeyboardOnly, isFalse);
    });

    test('plain shell, active, desktop, no toggle → autofocus off, hwkb-only on', () {
      final p = TerminalFocusPolicy.resolve(
        isTmux: false,
        isActive: true,
        forceSoftKeyboard: false,
        mobile: false,
      );
      expect(p.autofocus, isFalse);
      expect(p.hardwareKeyboardOnly, isTrue);
    });

    test('plain shell, inactive → autofocus off, hwkb-only on', () {
      final p = TerminalFocusPolicy.resolve(
        isTmux: false,
        isActive: false,
        forceSoftKeyboard: false,
        mobile: true,
      );
      expect(p.autofocus, isFalse);
      expect(p.hardwareKeyboardOnly, isTrue);
    });
  });
}