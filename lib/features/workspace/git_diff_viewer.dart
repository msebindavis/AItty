import 'package:flutter/material.dart';

import '../../core/constants/spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/obsidian_colors.dart';
import '../../models/git_models.dart';
import '../../utils/git_parsers.dart';

class GitDiffViewer extends StatelessWidget {
  const GitDiffViewer({super.key, required this.diff});

  final String diff;

  @override
  Widget build(BuildContext context) {
    final hunks = GitParsers.parseUnifiedDiff(diff);
    if (hunks.isEmpty) {
      return Center(
        child: Text(
          diff.trim().isEmpty ? 'No diff to display.' : diff,
          style: AppTypography.mono(size: 12, color: ObsidianColors.onSurfaceVariant),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: hunks.length,
      itemBuilder: (context, index) => _HunkView(hunk: hunks[index]),
    );
  }
}

class _HunkView extends StatelessWidget {
  const _HunkView({required this.hunk});

  final DiffHunk hunk;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              color: ObsidianColors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Text(
              hunk.header,
              style: AppTypography.mono(size: 11, color: ObsidianColors.primary),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...hunk.lines.map((line) => _DiffLineView(line: line)),
        ],
      ),
    );
  }
}

class _DiffLineView extends StatelessWidget {
  const _DiffLineView({required this.line});

  final DiffLine line;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, prefix) = switch (line.type) {
      DiffLineType.add => (ObsidianColors.secondaryContainer.withValues(alpha: 0.25), ObsidianColors.secondary, '+'),
      DiffLineType.remove => (ObsidianColors.error.withValues(alpha: 0.15), ObsidianColors.error, '-'),
      DiffLineType.context => (Colors.transparent, ObsidianColors.onSurfaceVariant, ' '),
      DiffLineType.header => (Colors.transparent, ObsidianColors.onSurfaceVariant, ' '),
    };

    return Container(
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(prefix, style: AppTypography.mono(size: 11, color: fg)),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: SelectableText(
              line.text,
              style: AppTypography.mono(size: 11, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}
