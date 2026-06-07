import 'package:flutter/material.dart';

import '../core/constants/spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/theme/obsidian_colors.dart';
import '../models/session.dart';
import 'status_chip.dart';

class ConnectionSessionCard extends StatelessWidget {
  const ConnectionSessionCard({
    super.key,
    required this.session,
    this.onTap,
    this.onLongPress,
    this.onDisconnect,
  });

  final Session session;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    final accent = _accentColor(session.state);
    return Material(
      color: ObsidianColors.surface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          border: Border.all(color: ObsidianColors.outlineVariant),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(AppSpacing.radiusXl)),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: onTap,
                  onLongPress: onLongPress,
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(AppSpacing.radiusXl)),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _SessionIcon(iconName: session.iconName, color: accent),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    session.title,
                                    style: AppTypography.inter(size: 20, weight: FontWeight.w500),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(session.connectionString, style: AppTypography.mono(size: 12)),
                                ],
                              ),
                            ),
                            StatusChip.session(state: session.state),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(AppSpacing.sm),
                          decoration: BoxDecoration(
                            color: ObsidianColors.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                            border: Border.all(color: ObsidianColors.outlineVariant),
                          ),
                          child: Text(
                            session.lastOutputLine,
                            style: AppTypography.mono(size: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (onDisconnect != null)
                IconButton(
                  icon: const Icon(Icons.close, size: 20, color: ObsidianColors.outline),
                  tooltip: 'End session',
                  onPressed: onDisconnect,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _accentColor(SessionState state) => switch (state) {
        SessionState.connected => ObsidianColors.secondary,
        SessionState.processing => ObsidianColors.tertiary,
        SessionState.awaitingInput => ObsidianColors.error,
        SessionState.idle => ObsidianColors.outline,
        SessionState.reconnecting => ObsidianColors.primary,
        SessionState.disconnected => ObsidianColors.outlineVariant,
      };
}

class _SessionIcon extends StatelessWidget {
  const _SessionIcon({required this.iconName, required this.color});

  final String iconName;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final icon = switch (iconName) {
      'database' => Icons.storage_outlined,
      'memory' => Icons.memory_outlined,
      _ => Icons.dns_outlined,
    };
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: ObsidianColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: ObsidianColors.outlineVariant),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}
