import 'package:flutter/material.dart';

import '../core/constants/spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/theme/obsidian_colors.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg, bottom: AppSpacing.sm),
      child: Text(
        title,
        style: AppTypography.mono(
          size: 12,
          weight: FontWeight.w500,
          color: ObsidianColors.onSurfaceVariant,
        ).copyWith(letterSpacing: 1.2),
      ),
    );
  }
}
