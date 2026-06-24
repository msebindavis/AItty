/// Decides how a terminal pane should be configured for focus and IME.
///
/// Plain (non-tmux) shells must NOT bring up the soft keyboard from a touch —
/// the toolbar keyboard icon is the only IME entry point. Hardware-keyboard
/// typing still works because the FocusNode is still attached; only the text
/// input connection is gated.
///
/// Centralising the rule here lets us unit-test it directly without having to
/// pump the full workspace tree, and gives one place to look at when we later
/// add more rules (e.g. per-host overrides).
class TerminalFocusPolicy {
  const TerminalFocusPolicy({
    required this.autofocus,
    required this.hardwareKeyboardOnly,
  });

  /// True if the [xterm.TerminalView] should claim focus on mount.
  final bool autofocus;

  /// True if hardware keyboard only should be enforced. When true, the platform
  /// soft IME is never shown on focus. When false, focus opens the IME on
  /// touch devices.
  final bool hardwareKeyboardOnly;

  /// Returns the focus policy for a pane given the gating inputs.
  ///
  /// Inputs:
  /// - [isTmux]: true if the pane is a tmux-managed shell; false for a plain
  ///   (raw SSH) shell.
  /// - [isActive]: true when the pane is the currently-selected tab.
  /// - [forceSoftKeyboard]: true when the user has explicitly requested the
  ///   soft keyboard via the toolbar's keyboard icon.
  /// - [mobile]: true on Android/iOS (where focus typically opens the IME).
  static TerminalFocusPolicy resolve({
    required bool isTmux,
    required bool isActive,
    required bool forceSoftKeyboard,
    required bool mobile,
  }) {
    final isPlainShell = !isTmux;
    return TerminalFocusPolicy(
      // Plain shells never autofocus — focus on tab mount/switch is what
      // opens the IME on touch. The toolbar keyboard icon still primes
      // focus via an explicit requestFocus call, which works regardless of
      // this prop.
      autofocus: isActive && !isPlainShell,
      // Plain shells: IME off by default; the toolbar keyboard icon is the
      // only way to flip it on. Tmux panes keep the existing rule (IME off
      // on desktop, off on mobile by default, on after toolbar toggle).
      hardwareKeyboardOnly: isPlainShell
          ? !forceSoftKeyboard
          : (!mobile || !forceSoftKeyboard),
    );
  }
}