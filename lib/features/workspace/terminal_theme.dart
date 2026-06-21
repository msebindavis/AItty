import 'package:xterm/xterm.dart';

/// Base font size for terminal cells. xterm's own default is 13px, which
/// reads large on a phone screen — we drop to 11px so a typical 80×24
/// tmux viewport fits comfortably on a portrait phone. Pinch-to-zoom
/// in the workspace still scales 0.75×–2× from this base.
const _terminalFontSize = 11.0;

/// Standard xterm palette and system monospace stack — no app-theme overrides.
const hostTerminalTextStyle = TerminalStyle(fontSize: _terminalFontSize);

const hostTerminalTheme = TerminalThemes.defaultTheme;
