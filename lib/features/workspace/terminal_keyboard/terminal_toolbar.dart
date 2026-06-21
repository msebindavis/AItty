import 'package:flutter/material.dart';

import '../../../core/theme/obsidian_colors.dart';

/// Toolbar actions emitted by [TerminalToolbar].
enum TerminalToolbarAction {
  touch,
  magicWand,
  star,
  braces,
  folder,
  shiftTab,
  settings,
  keyboardHide,
  more,
}

/// Universal terminal toolbar.
///
/// The first 7 icons live inside a horizontally-scrollable row so they
/// can be swiped left/right. The last two icons — keyboard-hide and the
/// three-dots cboard toggle — are pinned at the right edge and always
/// visible, like a chat input bar's trailing actions.
class TerminalToolbar extends StatelessWidget {
  const TerminalToolbar({
    super.key,
    required this.onToolbarAction,
    this.keyboardShown = true,
  });

  final ValueChanged<TerminalToolbarAction> onToolbarAction;

  /// Whether the system soft keyboard (and the cboard overlay) are
  /// currently visible. Drives the keyboard-hide icon and tooltip.
  final bool keyboardShown;

  /// Fixed width of each toolbar button.
  static const double buttonWidth = 48.0;

  /// Fixed height of the toolbar strip.
  static const double height = 32.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: const BoxDecoration(
        color: ObsidianColors.surfaceContainer,
      ),
      child: Row(
        children: [
          // Scrollable icons: touch, all keys, snippets, symbols, history,
          // shift+tab, settings. User can swipe left/right to reach them.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  _ToolbarButton(
                    icon: Icons.touch_app_outlined,
                    tooltip: 'Touch input',
                    onTap: () => onToolbarAction(TerminalToolbarAction.touch),
                  ),
                  _ToolbarButton(
                    icon: Icons.auto_fix_high,
                    tooltip: 'All keys',
                    onTap: () => onToolbarAction(TerminalToolbarAction.magicWand),
                  ),
                  _ToolbarButton(
                    icon: Icons.star_outline,
                    tooltip: 'Snippets',
                    onTap: () => onToolbarAction(TerminalToolbarAction.star),
                  ),
                  _ToolbarButton(
                    icon: Icons.code,
                    tooltip: 'Symbols',
                    onTap: () => onToolbarAction(TerminalToolbarAction.braces),
                  ),
                  _ToolbarButton(
                    icon: Icons.folder_outlined,
                    tooltip: 'History',
                    onTap: () => onToolbarAction(TerminalToolbarAction.folder),
                  ),
                  _ToolbarButton(
                    icon: Icons.keyboard_tab_outlined,
                    tooltip: 'Shift+Tab',
                    onTap: () => onToolbarAction(TerminalToolbarAction.shiftTab),
                  ),
                  _ToolbarButton(
                    icon: Icons.settings_outlined,
                    tooltip: 'Settings',
                    onTap: () => onToolbarAction(TerminalToolbarAction.settings),
                  ),
                ],
              ),
            ),
          ),
          // Faint divider between the scrollable region and the pinned
          // actions so users can tell where the scroll boundary is.
          Container(
            width: 0.5,
            height: height * 0.5,
            color: ObsidianColors.outlineVariant.withValues(alpha: 0.4),
          ),
          // Pinned actions: keyboard-hide (toggle) + three-dots cboard toggle.
          // Icon swaps based on [keyboardShown]:
          //   - shown   → keyboard_hide_outlined ("tap to hide")
          //   - hidden  → keyboard_outlined      ("tap to show")
          _ToolbarButton(
            icon: keyboardShown
                ? Icons.keyboard_hide_outlined
                : Icons.keyboard_outlined,
            tooltip: keyboardShown ? 'Hide keyboard' : 'Show keyboard',
            onTap: () => onToolbarAction(TerminalToolbarAction.keyboardHide),
          ),
          _ToolbarButton(
            icon: Icons.more_horiz,
            tooltip: 'Toggle cboard',
            onTap: () => onToolbarAction(TerminalToolbarAction.more),
          ),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final content = SizedBox(
      width: TerminalToolbar.buttonWidth,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Icon(
            icon,
            size: 18,
            color: ObsidianColors.onSurfaceVariant,
          ),
        ),
      ),
    );
    if (tooltip == null) return content;
    return Tooltip(message: tooltip!, child: content);
  }
}
