import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/obsidian_colors.dart';
import '../../../utils/terminal_input.dart';
import 'terminal_key_catalog.dart';

/// Termius-style 8-column key grid for terminal shortcuts. Renders only
/// the key grid — the toolbar above it is a separate [TerminalToolbar]
/// widget so it can sit at the top of the keyboard area in any
/// chat-style surface.
///
/// The panel mirrors the Termius reference layout: arrows + main
/// modifiers on row 1, secondary nav + modifiers on row 2, symbols
/// filling rows 3–6, F-keys rows 7–8, and ctrl shortcuts spilling into
/// row 9. The whole 9-row column is wrapped in a vertical
/// [SingleChildScrollView] so the user can swipe up/down to reach keys
/// that overflow the visible area. Each key's width is computed from
/// the panel width via [LayoutBuilder] so the 8 columns always fit
/// perfectly with no horizontal overflow.
class TerminalKeyboardPanel extends StatelessWidget {
  /// Approximate visible height of the cboard when shown. The internal
  /// 9-row grid can be slightly taller than this; the
  /// [SingleChildScrollView] lets the user reach the last row(s). The
  /// host uses this value to reserve the right amount of bottom inset
  /// for the terminal content above the cboard.
  static const double cboardHeight = 342.5;

  /// Number of columns in the grid. Matches the Termius reference.
  static const int columns = 8;

  /// Gap between adjacent keys, in logical pixels.
  static const double keyGap = 2.0;

  /// Height of every key.
  static const double keyHeight = 40.0;

  const TerminalKeyboardPanel({
    super.key,
    required this.ctrlActive,
    required this.altActive,
    required this.onKeyAction,
    required this.onArrow,
  });

  final bool ctrlActive;
  final bool altActive;
  final TerminalKeyHandler onKeyAction;
  final ValueChanged<TerminalArrowDirection> onArrow;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: cboardHeight,
      decoration: const BoxDecoration(
        color: ObsidianColors.surfaceContainer,
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        0,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Compute the per-key width from the panel width so 8
            // columns always fit perfectly. constraints.maxWidth is
            // the inner width after the Container's left/right padding
            // is consumed.
            final keyW =
                (constraints.maxWidth - (columns - 1) * keyGap) / columns;
            return SingleChildScrollView(
              scrollDirection: Axis.vertical,
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row1(keyW),
                  const SizedBox(height: keyGap),
                  _row2(keyW),
                  const SizedBox(height: keyGap),
                  _row3(keyW),
                  const SizedBox(height: keyGap),
                  _row4(keyW),
                  const SizedBox(height: keyGap),
                  _row5(keyW),
                  const SizedBox(height: keyGap),
                  _row6(keyW),
                  const SizedBox(height: keyGap),
                  _row7(keyW),
                  const SizedBox(height: keyGap),
                  _row8(keyW),
                  const SizedBox(height: keyGap),
                  _row9(keyW),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Row builders ─────────────────────────────────────────────────────
  // Each row has up to [columns] (8) cells. Cell order mirrors the
  // Termius reference where possible: arrows + main modifiers in row 1,
  // secondary nav + modifiers in row 2, symbols filling rows 3–6, F-keys
  // in rows 7–8, and ctrl shortcuts spilling into row 9 (4 cells).

  Widget _row1(double keyW) => _buildRow(keyW, [
        _arrowCell(Icons.keyboard_arrow_left, TerminalArrowDirection.left),
        _arrowCell(Icons.keyboard_arrow_up, TerminalArrowDirection.up),
        _arrowCell(Icons.keyboard_arrow_down, TerminalArrowDirection.down),
        _arrowCell(Icons.keyboard_arrow_right, TerminalArrowDirection.right),
        _keyCell('ESC', TerminalKeyAction.sendEsc),
        _keyCell('CTRL', TerminalKeyAction.toggleCtrl, active: ctrlActive),
        _keyCell('ALT', TerminalKeyAction.toggleAlt, active: altActive),
        _keyCell('TAB', TerminalKeyAction.sendTab),
      ]);

  Widget _row2(double keyW) => _buildRow(keyW, [
        _keyCell('Home', TerminalKeyAction.sendHome),
        _keyCell('Pg↑', TerminalKeyAction.sendPageUp),
        _keyCell('Pg↓', TerminalKeyAction.sendPageDown),
        _keyCell('End', TerminalKeyAction.sendEnd),
        _keyCell('↵', TerminalKeyAction.sendEnter),
        _keyCell('⇧TAB', TerminalKeyAction.sendShiftTab),
        _keyCell('INS', TerminalKeyAction.sendInsert),
        _keyCell('DEL', TerminalKeyAction.sendDelete),
      ]);

  Widget _row3(double keyW) => _buildRow(keyW, [
        _keyCell('|', TerminalKeyAction.sendSymbolPipe),
        _keyCell('!', TerminalKeyAction.sendSymbolExclamation),
        _keyCell('~', TerminalKeyAction.sendSymbolTilde),
        _keyCell(':', TerminalKeyAction.sendSymbolColon),
        _keyCell(';', TerminalKeyAction.sendSymbolSemicolon),
        _keyCell('"', TerminalKeyAction.sendSymbolDoubleQuote),
        _keyCell("'", TerminalKeyAction.sendSymbolQuote),
        _keyCell('#', TerminalKeyAction.sendSymbolHash),
      ]);

  Widget _row4(double keyW) => _buildRow(keyW, [
        _keyCell('\$', TerminalKeyAction.sendSymbolDollar),
        _keyCell('@', TerminalKeyAction.sendSymbolAt),
        _keyCell('%', TerminalKeyAction.sendSymbolPercent),
        _keyCell('^', TerminalKeyAction.sendSymbolCaret),
        _keyCell('&', TerminalKeyAction.sendSymbolAmpersand),
        _keyCell('*', TerminalKeyAction.sendSymbolStar),
        _keyCell('(', TerminalKeyAction.sendSymbolLeftParen),
        _keyCell(')', TerminalKeyAction.sendSymbolRightParen),
      ]);

  Widget _row5(double keyW) => _buildRow(keyW, [
        _keyCell('{', TerminalKeyAction.sendSymbolLeftBrace),
        _keyCell('}', TerminalKeyAction.sendSymbolRightBrace),
        _keyCell('[', TerminalKeyAction.sendSymbolLeftBracket),
        _keyCell(']', TerminalKeyAction.sendSymbolRightBracket),
        _keyCell('<', TerminalKeyAction.sendSymbolLess),
        _keyCell('>', TerminalKeyAction.sendSymbolGreater),
        _keyCell(',', TerminalKeyAction.sendSymbolComma),
        _keyCell('.', TerminalKeyAction.sendSymbolPeriod),
      ]);

  Widget _row6(double keyW) => _buildRow(keyW, [
        _keyCell('=', TerminalKeyAction.sendSymbolEquals),
        _keyCell('+', TerminalKeyAction.sendSymbolPlus),
        _keyCell('-', TerminalKeyAction.sendSymbolMinus),
        _keyCell('_', TerminalKeyAction.sendSymbolUnderscore),
        _keyCell('/', TerminalKeyAction.sendSymbolSlash),
        _keyCell('\\', TerminalKeyAction.sendSymbolBackslash),
        _keyCell('F1', TerminalKeyAction.sendFunction1),
        _keyCell('F2', TerminalKeyAction.sendFunction2),
      ]);

  Widget _row7(double keyW) => _buildRow(keyW, [
        _keyCell('F3', TerminalKeyAction.sendFunction3),
        _keyCell('F4', TerminalKeyAction.sendFunction4),
        _keyCell('F5', TerminalKeyAction.sendFunction5),
        _keyCell('F6', TerminalKeyAction.sendFunction6),
        _keyCell('F7', TerminalKeyAction.sendFunction7),
        _keyCell('F8', TerminalKeyAction.sendFunction8),
        _keyCell('F9', TerminalKeyAction.sendFunction9),
        _keyCell('F10', TerminalKeyAction.sendFunction10),
      ]);

  Widget _row8(double keyW) => _buildRow(keyW, [
        _keyCell('F11', TerminalKeyAction.sendFunction11),
        _keyCell('F12', TerminalKeyAction.sendFunction12),
        _keyCell('^C', TerminalKeyAction.sendCtrlC),
        _keyCell('^Z', TerminalKeyAction.sendCtrlZ),
        _keyCell('^D', TerminalKeyAction.sendCtrlD),
        _keyCell('^L', TerminalKeyAction.sendCtrlL),
        _keyCell('^A', TerminalKeyAction.sendCtrlA),
        _keyCell('^E', TerminalKeyAction.sendCtrlE),
      ]);

  Widget _row9(double keyW) => _buildRow(keyW, [
        _keyCell('^U', TerminalKeyAction.sendCtrlU),
        _keyCell('^K', TerminalKeyAction.sendCtrlK),
        _keyCell('^W', TerminalKeyAction.sendCtrlW),
        _keyCell('^R', TerminalKeyAction.sendCtrlR),
      ]);

  // ── Cell helpers ─────────────────────────────────────────────────────

  Widget _buildRow(double keyW, List<Widget> cells) {
    assert(cells.length <= columns,
        'Row has ${cells.length} cells; max is $columns.');
    return Row(
      children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0) const SizedBox(width: keyGap),
          SizedBox(width: keyW, child: cells[i]),
        ],
      ],
    );
  }

  Widget _keyCell(String label, TerminalKeyAction action, {bool active = false}) {
    return _KeyButton(
      label: label,
      active: active,
      onTap: () => onKeyAction(action),
    );
  }

  Widget _arrowCell(IconData icon, TerminalArrowDirection dir) {
    return _ArrowKey(
      icon: icon,
      onRepeat: () => onArrow(dir),
    );
  }
}

/// Termius-style single key. Width is taken from the parent (the row's
/// per-column [SizedBox]); the key fills whatever width it's given.
class _KeyButton extends StatelessWidget {
  const _KeyButton({
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active
          ? ObsidianColors.primary.withValues(alpha: 0.22)
          : ObsidianColors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: TerminalKeyboardPanel.keyHeight,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: ObsidianColors.outlineVariant.withValues(alpha: 0.25),
              width: 0.5,
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: AppTypography.inter(
                size: 15,
                weight: FontWeight.w700,
                color: active ? ObsidianColors.primary : ObsidianColors.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ArrowKey extends StatefulWidget {
  const _ArrowKey({
    required this.icon,
    required this.onRepeat,
  });

  final IconData icon;
  final VoidCallback onRepeat;

  @override
  State<_ArrowKey> createState() => _ArrowKeyState();
}

class _ArrowKeyState extends State<_ArrowKey> {
  Timer? _timer;

  void _start() {
    widget.onRepeat();
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 320), () {
      _timer = Timer.periodic(const Duration(milliseconds: 55), (_) => widget.onRepeat());
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // No `InkWell.onTap` here — the `Listener.onPointerDown` below is
    // the single source of truth for the press. Adding `onTap` would
    // double-fire `onRepeat` on every tap (once from `_start()`, once
    // from `InkWell`). The `InkWell` is kept (without a handler) for
    // its ripple/splash visual feedback on tap-and-release.
    return Listener(
      onPointerDown: (_) => _start(),
      onPointerUp: (_) => _stop(),
      onPointerCancel: (_) => _stop(),
      child: Material(
        color: ObsidianColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          child: Container(
            height: TerminalKeyboardPanel.keyHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: ObsidianColors.outlineVariant.withValues(alpha: 0.25),
                width: 0.5,
              ),
            ),
            child: Icon(widget.icon, size: 20, color: ObsidianColors.onSurface),
          ),
        ),
      ),
    );
  }
}