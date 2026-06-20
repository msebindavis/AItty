import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/obsidian_colors.dart';
import '../../../utils/terminal_input.dart';
import 'terminal_key_catalog.dart';

/// Modifier strip above the system keyboard for terminal shortcuts.
class TerminalKeyboardPanel extends StatelessWidget {
  const TerminalKeyboardPanel({
    super.key,
    required this.ctrlActive,
    required this.altActive,
    required this.keyboardActive,
    required this.onKeyAction,
    required this.onArrow,
  });

  final bool ctrlActive;
  final bool altActive;
  final bool keyboardActive;
  final TerminalKeyHandler onKeyAction;
  final ValueChanged<TerminalArrowDirection> onArrow;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.transparent,
        border: Border(top: BorderSide(color: ObsidianColors.outlineVariant, width: 0.5)),
      ),
      padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
      child: _ModifierStrip(
        ctrlActive: ctrlActive,
        altActive: altActive,
        keyboardActive: keyboardActive,
        onKeyAction: onKeyAction,
        onArrow: onArrow,
      ),
    );
  }
}

class _ModifierStrip extends StatelessWidget {
  const _ModifierStrip({
    required this.ctrlActive,
    required this.altActive,
    required this.keyboardActive,
    required this.onKeyAction,
    required this.onArrow,
  });

  final bool ctrlActive;
  final bool altActive;
  final bool keyboardActive;
  final TerminalKeyHandler onKeyAction;
  final ValueChanged<TerminalArrowDirection> onArrow;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _ModChip(label: 'ESC', onTap: () => onKeyAction(TerminalKeyAction.sendEsc)),
                _ModChip(label: '⇧TAB', onTap: () => onKeyAction(TerminalKeyAction.sendShiftTab)),
                _ModChip(
                  label: 'CTRL',
                  active: ctrlActive,
                  onTap: () => onKeyAction(TerminalKeyAction.toggleCtrl),
                ),
                _ModChip(
                  label: 'ALT',
                  active: altActive,
                  onTap: () => onKeyAction(TerminalKeyAction.toggleAlt),
                ),
                _ModChip(label: 'TAB', onTap: () => onKeyAction(TerminalKeyAction.sendTab)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        _ArrowKey(icon: Icons.keyboard_arrow_left, onRepeat: () => onArrow(TerminalArrowDirection.left)),
        _ArrowKey(icon: Icons.keyboard_arrow_up, onRepeat: () => onArrow(TerminalArrowDirection.up)),
        _ArrowKey(icon: Icons.keyboard_arrow_down, onRepeat: () => onArrow(TerminalArrowDirection.down)),
        _ArrowKey(icon: Icons.keyboard_arrow_right, onRepeat: () => onArrow(TerminalArrowDirection.right)),
        _IconModChip(
          icon: Icons.grid_view_rounded,
          tooltip: 'More keys, history & snippets',
          onTap: () => onKeyAction(TerminalKeyAction.openExtended),
        ),
        _IconModChip(
          icon: keyboardActive ? Icons.keyboard_hide_outlined : Icons.keyboard_outlined,
          tooltip: keyboardActive ? 'Hide keyboard' : 'Show keyboard',
          active: keyboardActive,
          onTap: () => onKeyAction(TerminalKeyAction.hideKeyboard),
        ),
      ],
    );
  }
}

class _ModChip extends StatelessWidget {
  const _ModChip({
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: active
            ? ObsidianColors.primary.withValues(alpha: 0.22)
            : ObsidianColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              border: Border.all(color: ObsidianColors.outlineVariant.withValues(alpha: 0.25)),
            ),
            child: Text(
              label,
              style: AppTypography.mono(
                size: 12,
                color: active ? ObsidianColors.primary : ObsidianColors.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _IconModChip extends StatelessWidget {
  const _IconModChip({
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final chip = Material(
      color: active
          ? ObsidianColors.primary.withValues(alpha: 0.22)
          : ObsidianColors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: Container(
          width: 36,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            border: Border.all(color: ObsidianColors.outlineVariant.withValues(alpha: 0.25)),
          ),
          child: Icon(
            icon,
            size: 18,
            color: active ? ObsidianColors.primary : ObsidianColors.onSurfaceVariant,
          ),
        ),
      ),
    );
    if (tooltip == null) return chip;
    return Tooltip(message: tooltip!, child: chip);
  }
}

class _ArrowKey extends StatefulWidget {
  const _ArrowKey({required this.icon, required this.onRepeat});

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
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Listener(
        onPointerDown: (_) => _start(),
        onPointerUp: (_) => _stop(),
        onPointerCancel: (_) => _stop(),
        child: Material(
          color: ObsidianColors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          child: InkWell(
            onTap: widget.onRepeat,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: Border.all(color: ObsidianColors.outlineVariant.withValues(alpha: 0.25)),
              ),
              child: Icon(widget.icon, size: 18, color: ObsidianColors.onSurface),
            ),
          ),
        ),
      ),
    );
  }
}
