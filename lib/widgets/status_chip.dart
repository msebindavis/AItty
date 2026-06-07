import 'package:flutter/material.dart';

import '../core/constants/spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/theme/obsidian_colors.dart';
import '../models/host.dart';
import '../models/session.dart';

class StatusChip extends StatelessWidget {
  const StatusChip.host({super.key, required HostReachability reachability, this.pulseDot = false})
      : _label = null,
        _color = null,
        _hostReachability = reachability,
        _sessionState = null;

  const StatusChip.session({super.key, required SessionState state, this.pulseDot = false})
      : _label = null,
        _color = null,
        _hostReachability = null,
        _sessionState = state;

  const StatusChip.label({super.key, required String label, required Color color, this.pulseDot = false})
      : _label = label,
        _color = color,
        _hostReachability = null,
        _sessionState = null;

  final String? _label;
  final Color? _color;
  final HostReachability? _hostReachability;
  final SessionState? _sessionState;
  final bool pulseDot;

  @override
  Widget build(BuildContext context) {
    final (label, color) = _resolve();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusDot(color: color, pulse: pulseDot),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTypography.mono(size: 12, color: color),
          ),
        ],
      ),
    );
  }

  (String, Color) _resolve() {
    if (_label != null && _color != null) return (_label!, _color!);
    if (_hostReachability != null) {
      return switch (_hostReachability!) {
        HostReachability.online => ('Online', ObsidianColors.secondary),
        HostReachability.offline => ('Offline', ObsidianColors.outline),
        HostReachability.unknown => ('Unknown', ObsidianColors.outline),
      };
    }
    return switch (_sessionState!) {
      SessionState.connected => ('Connected', ObsidianColors.secondary),
      SessionState.processing => ('Processing', ObsidianColors.primaryContainer),
      SessionState.awaitingInput => ('Awaiting Input', ObsidianColors.error),
      SessionState.idle => ('Idle', ObsidianColors.outline),
      SessionState.reconnecting => ('Reconnecting', ObsidianColors.primary),
      SessionState.disconnected => ('Disconnected', ObsidianColors.outline),
    };
  }
}

class _StatusDot extends StatefulWidget {
  const _StatusDot({required this.color, required this.pulse});

  final Color color;
  final bool pulse;

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    if (widget.pulse) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulse && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.pulse) {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.pulse) {
      return Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      );
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.4 + _controller.value * 0.6),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.35 * _controller.value),
                blurRadius: 4 * _controller.value,
                spreadRadius: 1 * _controller.value,
              ),
            ],
          ),
        );
      },
    );
  }
}

class TagChip extends StatelessWidget {
  const TagChip({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: ObsidianColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: ObsidianColors.outlineVariant),
      ),
      child: Text(label, style: AppTypography.mono(size: 12)),
    );
  }
}
