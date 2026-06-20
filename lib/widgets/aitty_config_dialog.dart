import 'package:flutter/material.dart';

import '../core/constants/spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/theme/obsidian_colors.dart';
import '../models/aitty_config.dart';

enum AittyConfigChoice { openWorkspace, createNew, cancel }

class AittyConfigResult {
  const AittyConfigResult({
    required this.choice,
    this.workspaceConfig,
  });

  final AittyConfigChoice choice;
  final AittyWorkspaceConfig? workspaceConfig;
}

class AittyConfigDialog extends StatelessWidget {
  const AittyConfigDialog({
    super.key,
    required this.path,
    required this.config,
  });

  final String path;
  final AittyConfig config;

  static Future<AittyConfigResult?> show(
    BuildContext context, {
    required String path,
    required AittyConfig config,
  }) {
    return showDialog<AittyConfigResult>(
      context: context,
      builder: (context) => AittyConfigDialog(path: path, config: config),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select your workspace'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
                itemCount: config.workspaces.length,
                separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.xs),
                itemBuilder: (context, index) {
                  final ws = config.workspaces[index];
                  return ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                      side: const BorderSide(color: ObsidianColors.outlineVariant),
                    ),
                    leading: const Icon(Icons.restore, color: ObsidianColors.primary),
                    title: Text(ws.name, style: AppTypography.inter(size: 14, weight: FontWeight.w600)),
                    subtitle: Text('${ws.terminals.length} terminal(s), ${ws.auxTabs.length} tab(s)'),
                    onTap: () {
                      Navigator.pop(
                        context,
                        AittyConfigResult(choice: AittyConfigChoice.openWorkspace, workspaceConfig: ws),
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
            const AittyConfigResult(choice: AittyConfigChoice.cancel),
          ),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            const AittyConfigResult(choice: AittyConfigChoice.createNew),
          ),
          child: const Text('Create New'),
        ),
      ],
    );
  }
}
