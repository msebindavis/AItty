import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/obsidian_colors.dart';
import '../../../utils/terminal_input.dart';
import 'terminal_key_catalog.dart';

/// Termius-style 8-row key grid for terminal shortcuts. Renders only the
/// key grid — the toolbar above it is a separate
/// [TerminalToolbar] widget so it can sit at the top of the keyboard area
/// in any chat-style surface.
class TerminalKeyboardPanel extends StatelessWidget {
  /// Approximate total rendered height of the key grid
  /// (divider 0.5 + 8 key rows × 40 + 7 row gaps × 2 + bottom padding 8).
  /// Used by the host screen to reserve space when the cboard is overlaid
  /// on top of the system soft keyboard.
  static const double cboardHeight = 342.5;

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
            final width = constraints.maxWidth;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ModifierRow(
                  ctrlActive: ctrlActive,
                  altActive: altActive,
                  onKeyAction: onKeyAction,
                ),
                const SizedBox(height: 2),
                _SymbolRow1(
                  width: width,
                  onKeyAction: onKeyAction,
                  onArrow: onArrow,
                ),
                const SizedBox(height: 2),
                _SymbolRow2(width: width, onKeyAction: onKeyAction),
                const SizedBox(height: 2),
                _SymbolRow3(width: width, onKeyAction: onKeyAction),
                const SizedBox(height: 2),
                _FunctionRow1(width: width, onKeyAction: onKeyAction),
                const SizedBox(height: 2),
                _FunctionRow2(width: width, onKeyAction: onKeyAction),
                const SizedBox(height: 2),
                _NavRow(width: width, onKeyAction: onKeyAction, onArrow: onArrow),
                const SizedBox(height: 2),
                _CtrlRow(width: width, onKeyAction: onKeyAction),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ModifierRow extends StatelessWidget {
  const _ModifierRow({
    required this.ctrlActive,
    required this.altActive,
    required this.onKeyAction,
  });

  final bool ctrlActive;
  final bool altActive;
  final TerminalKeyHandler onKeyAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _KeyButton(
          label: 'ESC',
          onTap: () => onKeyAction(TerminalKeyAction.sendEsc),
        ),
        const SizedBox(width: 2),
        _KeyButton(
          label: '⇧TAB',
          onTap: () => onKeyAction(TerminalKeyAction.sendShiftTab),
        ),
        const SizedBox(width: 2),
        _KeyButton(
          label: 'CTRL',
          active: ctrlActive,
          onTap: () => onKeyAction(TerminalKeyAction.toggleCtrl),
        ),
        const SizedBox(width: 2),
        _KeyButton(
          label: 'ALT',
          active: altActive,
          onTap: () => onKeyAction(TerminalKeyAction.toggleAlt),
        ),
        const SizedBox(width: 2),
        _KeyButton(
          label: 'TAB',
          onTap: () => onKeyAction(TerminalKeyAction.sendTab),
        ),
        const SizedBox(width: 2),
        _KeyButton(
          label: '↵',
          onTap: () => onKeyAction(TerminalKeyAction.sendEnter),
        ),
      ],
    );
  }
}

class _SymbolRow1 extends StatelessWidget {
  const _SymbolRow1({
    required this.width,
    required this.onKeyAction,
    required this.onArrow,
  });

  final double width;
  final TerminalKeyHandler onKeyAction;
  final ValueChanged<TerminalArrowDirection> onArrow;

  // 10 symbol keys + 1 down-arrow column on the right.
  static const _keys = <(String, TerminalKeyAction)>[
    ('|', TerminalKeyAction.sendSymbolPipe),
    ('!', TerminalKeyAction.sendSymbolExclamation),
    ('~', TerminalKeyAction.sendSymbolTilde),
    (':', TerminalKeyAction.sendSymbolColon),
    (';', TerminalKeyAction.sendSymbolSemicolon),
    ('"', TerminalKeyAction.sendSymbolDoubleQuote),
    ("'", TerminalKeyAction.sendSymbolQuote),
    ('#', TerminalKeyAction.sendSymbolHash),
    ('\$', TerminalKeyAction.sendSymbolDollar),
    ('@', TerminalKeyAction.sendSymbolAt),
  ];

  @override
  Widget build(BuildContext context) {
    // 10 symbol keys + 1 down arrow = 11 equal-width columns.
    final keyW = _keyWidthFor(width, 11);
    return Row(
      children: [
        for (final k in _keys) ...[
          _KeyButton(
            label: k.$1,
            width: keyW,
            onTap: () => onKeyAction(k.$2),
          ),
          const SizedBox(width: 2),
        ],
        _ArrowKey(
          icon: Icons.keyboard_arrow_down,
          onRepeat: () => onArrow(TerminalArrowDirection.down),
          width: keyW,
        ),
      ],
    );
  }
}

class _SymbolRow2 extends StatelessWidget {
  const _SymbolRow2({required this.width, required this.onKeyAction});

  final double width;
  final TerminalKeyHandler onKeyAction;

  static const _keys = <(String, TerminalKeyAction)>[
    ('%', TerminalKeyAction.sendSymbolPercent),
    ('^', TerminalKeyAction.sendSymbolCaret),
    ('&', TerminalKeyAction.sendSymbolAmpersand),
    ('*', TerminalKeyAction.sendSymbolStar),
    ('(', TerminalKeyAction.sendSymbolLeftParen),
    (')', TerminalKeyAction.sendSymbolRightParen),
    ('{', TerminalKeyAction.sendSymbolLeftBrace),
    ('}', TerminalKeyAction.sendSymbolRightBrace),
    ('[', TerminalKeyAction.sendSymbolLeftBracket),
    (']', TerminalKeyAction.sendSymbolRightBracket),
  ];

  @override
  Widget build(BuildContext context) {
    final keyW = _keyWidthFor(width, 10);
    return Row(
      children: [
        for (final k in _keys) ...[
          _KeyButton(
            label: k.$1,
            width: keyW,
            onTap: () => onKeyAction(k.$2),
          ),
          const SizedBox(width: 2),
        ],
      ],
    );
  }
}

class _SymbolRow3 extends StatelessWidget {
  const _SymbolRow3({required this.width, required this.onKeyAction});

  final double width;
  final TerminalKeyHandler onKeyAction;

  static const _keys = <(String, TerminalKeyAction)>[
    ('<', TerminalKeyAction.sendSymbolLess),
    ('>', TerminalKeyAction.sendSymbolGreater),
    (',', TerminalKeyAction.sendSymbolComma),
    ('.', TerminalKeyAction.sendSymbolPeriod),
    ('=', TerminalKeyAction.sendSymbolEquals),
    ('+', TerminalKeyAction.sendSymbolPlus),
    ('-', TerminalKeyAction.sendSymbolMinus),
    ('_', TerminalKeyAction.sendSymbolUnderscore),
    ('/', TerminalKeyAction.sendSymbolSlash),
    ('\\', TerminalKeyAction.sendSymbolBackslash),
  ];

  @override
  Widget build(BuildContext context) {
    final keyW = _keyWidthFor(width, 10);
    return Row(
      children: [
        for (final k in _keys) ...[
          _KeyButton(
            label: k.$1,
            width: keyW,
            onTap: () => onKeyAction(k.$2),
          ),
          const SizedBox(width: 2),
        ],
      ],
    );
  }
}

class _FunctionRow1 extends StatelessWidget {
  const _FunctionRow1({required this.width, required this.onKeyAction});

  final double width;
  final TerminalKeyHandler onKeyAction;

  @override
  Widget build(BuildContext context) {
    final keyW = _keyWidthFor(width, 6);
    return Row(
      children: [
        for (var i = 1; i <= 6; i++) ...[
          _KeyButton(
            label: 'F$i',
            width: keyW,
            onTap: () => onKeyAction(_fnAction(i)),
          ),
          const SizedBox(width: 2),
        ],
      ],
    );
  }
}

class _FunctionRow2 extends StatelessWidget {
  const _FunctionRow2({required this.width, required this.onKeyAction});

  final double width;
  final TerminalKeyHandler onKeyAction;

  @override
  Widget build(BuildContext context) {
    final keyW = _keyWidthFor(width, 6);
    return Row(
      children: [
        for (var i = 7; i <= 12; i++) ...[
          _KeyButton(
            label: 'F$i',
            width: keyW,
            onTap: () => onKeyAction(_fnAction(i)),
          ),
          const SizedBox(width: 2),
        ],
      ],
    );
  }
}

TerminalKeyAction _fnAction(int n) => switch (n) {
      1 => TerminalKeyAction.sendFunction1,
      2 => TerminalKeyAction.sendFunction2,
      3 => TerminalKeyAction.sendFunction3,
      4 => TerminalKeyAction.sendFunction4,
      5 => TerminalKeyAction.sendFunction5,
      6 => TerminalKeyAction.sendFunction6,
      7 => TerminalKeyAction.sendFunction7,
      8 => TerminalKeyAction.sendFunction8,
      9 => TerminalKeyAction.sendFunction9,
      10 => TerminalKeyAction.sendFunction10,
      11 => TerminalKeyAction.sendFunction11,
      _ => TerminalKeyAction.sendFunction12,
    };

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.width,
    required this.onKeyAction,
    required this.onArrow,
  });

  final double width;
  final TerminalKeyHandler onKeyAction;
  final ValueChanged<TerminalArrowDirection> onArrow;

  @override
  Widget build(BuildContext context) {
    final keyW = _keyWidthFor(width, 8);
    return Row(
      children: [
        _ArrowKey(
          icon: Icons.keyboard_arrow_left,
          onRepeat: () => onArrow(TerminalArrowDirection.left),
          width: keyW,
        ),
        const SizedBox(width: 2),
        _ArrowKey(
          icon: Icons.keyboard_arrow_up,
          onRepeat: () => onArrow(TerminalArrowDirection.up),
          width: keyW,
        ),
        const SizedBox(width: 2),
        _ArrowKey(
          icon: Icons.keyboard_arrow_down,
          onRepeat: () => onArrow(TerminalArrowDirection.down),
          width: keyW,
        ),
        const SizedBox(width: 2),
        _ArrowKey(
          icon: Icons.keyboard_arrow_right,
          onRepeat: () => onArrow(TerminalArrowDirection.right),
          width: keyW,
        ),
        const SizedBox(width: 2),
        _KeyButton(
          label: 'Home',
          width: keyW,
          onTap: () => onKeyAction(TerminalKeyAction.sendHome),
        ),
        const SizedBox(width: 2),
        _KeyButton(
          label: 'End',
          width: keyW,
          onTap: () => onKeyAction(TerminalKeyAction.sendEnd),
        ),
        const SizedBox(width: 2),
        _KeyButton(
          label: 'Pg↑',
          width: keyW,
          onTap: () => onKeyAction(TerminalKeyAction.sendPageUp),
        ),
        const SizedBox(width: 2),
        _KeyButton(
          label: 'Pg↓',
          width: keyW,
          onTap: () => onKeyAction(TerminalKeyAction.sendPageDown),
        ),
      ],
    );
  }
}

class _CtrlRow extends StatelessWidget {
  const _CtrlRow({required this.width, required this.onKeyAction});

  final double width;
  final TerminalKeyHandler onKeyAction;

  @override
  Widget build(BuildContext context) {
    final keyW = _keyWidthFor(width, 10);
    return Row(
      children: [
        _KeyButton(label: '^C', width: keyW, onTap: () => onKeyAction(TerminalKeyAction.sendCtrlC)),
        const SizedBox(width: 2),
        _KeyButton(label: '^Z', width: keyW, onTap: () => onKeyAction(TerminalKeyAction.sendCtrlZ)),
        const SizedBox(width: 2),
        _KeyButton(label: '^D', width: keyW, onTap: () => onKeyAction(TerminalKeyAction.sendCtrlD)),
        const SizedBox(width: 2),
        _KeyButton(label: '^L', width: keyW, onTap: () => onKeyAction(TerminalKeyAction.sendCtrlL)),
        const SizedBox(width: 2),
        _KeyButton(label: '^A', width: keyW, onTap: () => onKeyAction(TerminalKeyAction.sendCtrlA)),
        const SizedBox(width: 2),
        _KeyButton(label: '^E', width: keyW, onTap: () => onKeyAction(TerminalKeyAction.sendCtrlE)),
        const SizedBox(width: 2),
        _KeyButton(label: '^U', width: keyW, onTap: () => onKeyAction(TerminalKeyAction.sendCtrlU)),
        const SizedBox(width: 2),
        _KeyButton(label: '^K', width: keyW, onTap: () => onKeyAction(TerminalKeyAction.sendCtrlK)),
        const SizedBox(width: 2),
        _KeyButton(label: '^W', width: keyW, onTap: () => onKeyAction(TerminalKeyAction.sendCtrlW)),
        const SizedBox(width: 2),
        _KeyButton(label: '^R', width: keyW, onTap: () => onKeyAction(TerminalKeyAction.sendCtrlR)),
      ],
    );
  }
}

double _keyWidthFor(double rowWidth, int keys) {
  const gap = 2.0;
  return (rowWidth - gap * (keys - 1)) / keys;
}

/// Termius-style single key.
class _KeyButton extends StatelessWidget {
  const _KeyButton({
    required this.label,
    required this.onTap,
    this.width,
    this.active = false,
  });

  final String label;
  final VoidCallback onTap;
  final double? width;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final btn = Material(
      color: active
          ? ObsidianColors.primary.withValues(alpha: 0.22)
          : ObsidianColors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: width,
          height: 40,
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
    return btn;
  }
}

class _ArrowKey extends StatefulWidget {
  const _ArrowKey({
    required this.icon,
    required this.onRepeat,
    this.width,
  });

  final IconData icon;
  final VoidCallback onRepeat;
  final double? width;

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
    return Listener(
      onPointerDown: (_) => _start(),
      onPointerUp: (_) => _stop(),
      onPointerCancel: (_) => _stop(),
      child: Material(
        color: ObsidianColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: widget.onRepeat,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            width: widget.width,
            height: 40,
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
