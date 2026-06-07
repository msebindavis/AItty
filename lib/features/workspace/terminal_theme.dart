import 'package:xterm/xterm.dart';

import '../../core/theme/obsidian_colors.dart';

/// Fixed style — avoids Google Fonts work during terminal mount.
const obsidianTerminalTextStyle = TerminalStyle(fontFamily: 'monospace');

final obsidianTerminalTheme = TerminalTheme(
  cursor: ObsidianColors.primary,
  selection: ObsidianColors.primary.withValues(alpha: 0.35),
  foreground: ObsidianColors.onSurface,
  background: ObsidianColors.terminalBackground,
  black: ObsidianColors.surfaceContainerLowest,
  red: ObsidianColors.error,
  green: ObsidianColors.terminalTeal,
  yellow: ObsidianColors.tertiary,
  blue: ObsidianColors.terminalBlue,
  magenta: ObsidianColors.tertiary,
  cyan: ObsidianColors.primary,
  white: ObsidianColors.onSurface,
  brightBlack: ObsidianColors.outline,
  brightRed: ObsidianColors.error,
  brightGreen: ObsidianColors.secondary,
  brightYellow: ObsidianColors.tertiary,
  brightBlue: ObsidianColors.primaryContainer,
  brightMagenta: ObsidianColors.tertiary,
  brightCyan: ObsidianColors.primary,
  brightWhite: ObsidianColors.onSurface,
  searchHitBackground: ObsidianColors.primaryContainer.withValues(alpha: 0.4),
  searchHitBackgroundCurrent: ObsidianColors.primary.withValues(alpha: 0.5),
  searchHitForeground: ObsidianColors.onSurface,
);
