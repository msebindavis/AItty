import 'package:flutter/material.dart';

import '../core/constants/spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/theme/obsidian_colors.dart';
import '../models/host.dart';
import 'status_chip.dart';

class HostListTile extends StatelessWidget {
  const HostListTile({
    super.key,
    required this.host,
    this.onTap,
    this.onMenu,
  });

  final Host host;
  final VoidCallback? onTap;
  final VoidCallback? onMenu;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ObsidianColors.surfaceContainer,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            border: Border.all(color: ObsidianColors.outlineVariant),
          ),
          child: Row(
            children: [
              _HostIcon(host: host),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(host.label, style: AppTypography.inter(size: 16, weight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(host.hostname, style: AppTypography.mono(size: 12)),
                  ],
                ),
              ),
              StatusChip.host(reachability: host.reachability),
              IconButton(
                icon: const Icon(Icons.more_vert, color: ObsidianColors.outline),
                onPressed: onMenu,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HostIcon extends StatelessWidget {
  const _HostIcon({required this.host});

  final Host host;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: ObsidianColors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: ObsidianColors.outlineVariant),
      ),
      child: Icon(_iconFor(host), color: ObsidianColors.primary, size: 22),
    );
  }

  IconData _iconFor(Host host) {
    if (host.label.toLowerCase().contains('db')) return Icons.storage_outlined;
    if (host.label.toLowerCase().contains('ml')) return Icons.memory_outlined;
    return Icons.dns_outlined;
  }
}
