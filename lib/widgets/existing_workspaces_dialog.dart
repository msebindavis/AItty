import 'package:flutter/material.dart';

import '../core/constants/spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/theme/obsidian_colors.dart';
import '../models/workspace.dart';

enum ExistingWorkspaceChoice { openExisting, createNew, cancel }

class ExistingWorkspacesResult {
  const ExistingWorkspacesResult({
    required this.choice,
    this.workspaceId,
  });

  final ExistingWorkspaceChoice choice;
  final String? workspaceId;
}

class ExistingWorkspacesDialog extends StatelessWidget {
  const ExistingWorkspacesDialog({
    super.key,
    required this.path,
    required this.workspaces,
  });

  final String path;
  final List<Workspace> workspaces;

  static Future<ExistingWorkspacesResult?> show(
    BuildContext context, {
    required String path,
    required List<Workspace> workspaces,
  }) {
    return showDialog<ExistingWorkspacesResult>(
      context: context,
      builder: (context) => ExistingWorkspacesDialog(path: path, workspaces: workspaces),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Workspaces Found'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'There are already open workspaces on this path:',
              style: AppTypography.inter(size: 14),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              path,
              style: AppTypography.mono(size: 12, color: ObsidianColors.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.md),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: workspaces.length,
                separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.xs),
                itemBuilder: (context, index) {
                  final ws = workspaces[index];
                  return ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                      side: const BorderSide(color: ObsidianColors.outlineVariant),
                    ),
                    leading: const Icon(Icons.dashboard_outlined, color: ObsidianColors.primary),
                    title: Text(ws.name, style: AppTypography.inter(size: 14, weight: FontWeight.w600)),
                    subtitle: Text('${ws.terminals.length} terminal(s)'),
                    onTap: () {
                      Navigator.pop(
                        context,
                        ExistingWorkspacesResult(choice: ExistingWorkspaceChoice.openExisting, workspaceId: ws.id),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            const ExistingWorkspacesResult(choice: ExistingWorkspaceChoice.cancel),
          ),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            const ExistingWorkspacesResult(choice: ExistingWorkspaceChoice.createNew),
          ),
          child: const Text('Create New'),
        ),
      ],
    );
  }
}
