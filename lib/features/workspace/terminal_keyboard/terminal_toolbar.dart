import 'package:flutter/material.dart';

import '../../../core/theme/obsidian_colors.dart';

/// Toolbar actions emitted by [TerminalToolbar].
///
/// The new toolbar is a tight 9-icon strip: only the keys/actions a
/// terminal user reaches for repeatedly. Less-frequent affordances
/// (snippets, symbols, F-keys, the extended sheet) stay reachable from
/// the cboard grid, the [ExtendedKeyboardSheet], or the workspace
/// `+` overflow menu.
enum TerminalToolbarAction {
  /// Send ESC.
  esc,

  /// Send TAB.
  tab,

  /// Toggle the sticky Ctrl modifier.
  toggleCtrl,

  /// Toggle the floating arrow-pad bubble.
  arrows,

  /// Paste the system clipboard into the command bar.
  clipboard,

  /// Recent-commands quick menu (handled inside the toolbar).
  history,

  /// Toggle the chat-style command input bar.
  chat,

  /// Toggle the system soft keyboard (show or hide).
  keyboardHide,

  /// Toggle the cboard overlay.
  more,
}

/// Universal terminal toolbar — slim 9-icon strip.
///
/// Every icon is a primary affordance; there is no pinned/scrollable
/// split anymore. On narrow phones the row overflows rather than
/// scrolling (the host can wrap it in a horizontal [SingleChildScrollView]
/// if it needs to — the toolbar itself is a fixed-size [Container]).
class TerminalToolbar extends StatelessWidget {
  const TerminalToolbar({
    super.key,
    required this.onToolbarAction,
    this.keyboardShown = true,
    this.ctrlActive = false,
    this.arrowPadOpen = false,
    required this.onArrowPadToggleRequested,
    required this.onHistoryPicked,
    required this.recentCommands,
  });

  final ValueChanged<TerminalToolbarAction> onToolbarAction;

  /// Whether the system soft keyboard (and the cboard overlay) are
  /// currently visible. Drives the keyboard-hide icon and tooltip.
  final bool keyboardShown;

  /// Sticky Ctrl highlight.
  final bool ctrlActive;

  /// Whether the floating arrow pad is currently visible. Drives the
  /// arrows icon's filled-vs-outlined state.
  final bool arrowPadOpen;

  /// Called when the user taps the arrows icon. The host toggles its
  /// own [OverlayPortalController] and updates a [bool] state field
  /// that is fed back via [arrowPadOpen] so the icon follows the overlay.
  final VoidCallback onArrowPadToggleRequested;

  /// Called when the user picks a command from the history quick menu.
  final ValueChanged<String> onHistoryPicked;

  /// Recent commands for the history quick menu.
  final List<String> recentCommands;

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
      // Layout: a horizontally-scrollable strip of the 7 leftmost icons
      // (Esc / Tab / Ctrl / Arrows / Clipboard / History / Chat), a
      // faint vertical divider, then the 2 rightmost icons (Keyboard
      // and ⋯) pinned at the right edge. The pinned icons never scroll
      // off-screen, mirroring the chat-input-bar "trailing actions"
      // pattern. On phones wider than 7 × 48 = 336 dp the scroll view
      // is a no-op.
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              child: Row(
                children: [
                  // 1. Esc — text label, not an icon.
                  _ToolbarButton(
                    tooltip: 'Esc',
                    onTap: () => onToolbarAction(TerminalToolbarAction.esc),
                    child: const _KeyCapLabel('ESC'),
                  ),
                  // 2. Tab — text label, not an icon.
                  _ToolbarButton(
                    tooltip: 'Tab',
                    onTap: () => onToolbarAction(TerminalToolbarAction.tab),
                    child: const _KeyCapLabel('TAB'),
                  ),
                  // 3. Sticky Ctrl — text "CTRL" key-cap. Stays
                  //    highlighted while active so the user can apply
                  //    it to multiple cboard taps (e.g. ^C then ^X
                  //    without re-tapping Ctrl).
                  _ToolbarButton(
                    tooltip: 'Toggle Ctrl',
                    active: ctrlActive,
                    onTap: () =>
                        onToolbarAction(TerminalToolbarAction.toggleCtrl),
                    child: const _KeyCapLabel('CTRL'),
                  ),
                  // 4. Arrows — icon's filled/outlined state follows
                  //    [arrowPadOpen].
                  _ToolbarButton(
                    tooltip: 'Arrow pad',
                    active: arrowPadOpen,
                    onTap: onArrowPadToggleRequested,
                    child: Icon(
                      arrowPadOpen
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_up_outlined,
                      size: 18,
                      color: arrowPadOpen
                          ? ObsidianColors.primary
                          : ObsidianColors.onSurfaceVariant,
                    ),
                  ),
                  // 5. Clipboard
                  _ToolbarButton(
                    tooltip: 'Paste from clipboard',
                    onTap: () =>
                        onToolbarAction(TerminalToolbarAction.clipboard),
                    child: const Icon(Icons.content_paste_outlined, size: 18),
                  ),
                  // 6. History — a PopupMenuButton so it owns the
                  //    tap-anchored menu and the menu closes on
                  //    outside tap automatically. The outer
                  //    `_ToolbarButton` carries no tooltip here so we
                  //    don't end up with two RawTooltip widgets for
                  //    "History" (the PopupMenuButton has its own).
                  _ToolbarButton(
                    tooltip: null,
                    onTap: () {},
                    child: PopupMenuButton<String>(
                      tooltip: 'History',
                      icon: const Icon(Icons.history, size: 18),
                      onSelected: onHistoryPicked,
                      itemBuilder: (_) => [
                        for (final cmd in recentCommands)
                          PopupMenuItem<String>(
                            value: cmd,
                            child: Text(
                              cmd,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        if (recentCommands.isEmpty)
                          const PopupMenuItem<String>(
                            enabled: false,
                            child: Text(
                              'No history yet',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // 7. Chat (command bar toggle)
                  _ToolbarButton(
                    tooltip: 'Toggle command bar',
                    onTap: () => onToolbarAction(TerminalToolbarAction.chat),
                    child: const Icon(Icons.chat_bubble_outline, size: 18),
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
          // 8. Keyboard (toggle IME) — pinned.
          _ToolbarButton(
            tooltip: keyboardShown ? 'Hide keyboard' : 'Show keyboard',
            onTap: () => onToolbarAction(TerminalToolbarAction.keyboardHide),
            child: Icon(
              keyboardShown
                  ? Icons.keyboard_hide_outlined
                  : Icons.keyboard_outlined,
              size: 18,
            ),
          ),
          // 9. ⋯ (cboard toggle) — pinned.
          _ToolbarButton(
            tooltip: 'Toggle cboard',
            onTap: () => onToolbarAction(TerminalToolbarAction.more),
            child: const Icon(Icons.more_horiz, size: 18),
          ),
        ],
      ),
    );
  }
}

/// Small text key-cap for the Esc / Tab / Ctrl toolbar buttons. Keeps
/// the buttons visually consistent (all three read as "keys", not icons)
/// and gives the user a recognizable key name at a glance.
class _KeyCapLabel extends StatelessWidget {
  const _KeyCapLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
        color: ObsidianColors.onSurface,
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.onTap,
    required this.child,
    this.tooltip,
    this.active = false,
  });

  final VoidCallback onTap;
  final Widget child;
  final String? tooltip;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final content = SizedBox(
      width: TerminalToolbar.buttonWidth,
      child: Material(
        color: active
            ? ObsidianColors.primary.withValues(alpha: 0.22)
            : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Center(
            child: IconTheme(
              data: IconThemeData(
                size: 18,
                color: active
                    ? ObsidianColors.primary
                    : ObsidianColors.onSurfaceVariant,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
    if (tooltip == null) return content;
    return Tooltip(message: tooltip!, child: content);
  }
}
