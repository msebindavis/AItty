import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/spacing.dart';
import '../../core/theme/obsidian_colors.dart';

class Scrolly extends StatefulWidget {
  const Scrolly({
    super.key,
    required this.onLineUp,
    required this.onLineDown,
    required this.onPageUp,
    required this.onPageDown,
    required this.onTop,
    required this.onLive,
    required this.onDone,
    required this.onThumbDrag,
    this.idleTimeout = const Duration(seconds: 3),
    required this.onHide,
  });

  final VoidCallback onLineUp;
  final VoidCallback onLineDown;
  final VoidCallback onPageUp;
  final VoidCallback onPageDown;
  final VoidCallback onTop;
  final VoidCallback onLive;
  final VoidCallback onDone;
  final ValueChanged<double> onThumbDrag;
  final Duration idleTimeout;
  final VoidCallback onHide;

  @override
  State<Scrolly> createState() => _ScrollyState();
}

class _ScrollyState extends State<Scrolly> with SingleTickerProviderStateMixin {
  Timer? _idleTimer;
  late AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fadeController.forward();
    _resetTimer();
  }

  @override
  void didUpdateWidget(covariant Scrolly oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resetTimer();
    if (_fadeController.isDismissed) {
      _fadeController.forward();
    }
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  void _resetTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(widget.idleTimeout, () {
      if (mounted) {
        _fadeController.reverse().then((_) {
          if (mounted) widget.onHide();
        });
      }
    });
  }

  void _handleAction(VoidCallback action) {
    _resetTimer();
    action();
  }

  Widget _buildButton({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
    bool isHoldable = false,
  }) {
    Timer? holdTimer;

    return GestureDetector(
      onTap: () => _handleAction(onTap),
      onLongPressStart: isHoldable
          ? (_) {
              _handleAction(onTap);
              holdTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
                _handleAction(onTap);
              });
            }
          : null,
      onLongPressEnd: isHoldable
          ? (_) {
              holdTimer?.cancel();
            }
          : null,
      onLongPressCancel: isHoldable
          ? () {
              holdTimer?.cancel();
            }
          : null,
      child: Container(
        width: 40,
        height: 40,
        color: Colors.transparent, // expand hit area
        child: Tooltip(
          message: tooltip ?? '',
          child: Icon(icon, size: 20, color: ObsidianColors.onSurface),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeController,
      child: MouseRegion(
        onEnter: (_) => _idleTimer?.cancel(),
        onExit: (_) => _resetTimer(),
        child: Container(
          width: 44,
          decoration: BoxDecoration(
            // Very low alpha so terminal text stays readable right
            // through the widget. No backdrop blur — blur is what
            // kills legibility; here we just want a faint glass tint
            // so the user can see where the scrolly ends.
            color: ObsidianColors.surfaceContainerHigh.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.10),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildButton(
                    icon: Icons.keyboard_arrow_up,
                    onTap: widget.onLineUp,
                    tooltip: 'Line up',
                    isHoldable: true,
                  ),
                  GestureDetector(
                    onPanUpdate: (details) {
                      _resetTimer();
                      widget.onThumbDrag(details.delta.dy);
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      color: Colors.transparent,
                      child: const Icon(Icons.drag_handle, size: 20, color: ObsidianColors.primary),
                    ),
                  ),
                  _buildButton(
                    icon: Icons.keyboard_arrow_down,
                    onTap: widget.onLineDown,
                    tooltip: 'Line down',
                    isHoldable: true,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Divider(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  _buildButton(
                    icon: Icons.keyboard_double_arrow_up,
                    onTap: widget.onPageUp,
                    tooltip: 'Page up',
                    isHoldable: true,
                  ),
                  _buildButton(
                    icon: Icons.keyboard_double_arrow_down,
                    onTap: widget.onPageDown,
                    tooltip: 'Page down',
                    isHoldable: true,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Divider(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  _buildButton(
                    icon: Icons.vertical_align_top,
                    onTap: widget.onTop,
                    tooltip: 'Top',
                  ),
                  _buildButton(
                    icon: Icons.vertical_align_bottom,
                    onTap: widget.onLive,
                    tooltip: 'Live',
                  ),
                  const SizedBox(height: 8),
                  _buildButton(
                    icon: Icons.close,
                    onTap: widget.onDone,
                    tooltip: 'Done',
                  ),
                ],
              ),
            ),
          ),
        );
  }
}
