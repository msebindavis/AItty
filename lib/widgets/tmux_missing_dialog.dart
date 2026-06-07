import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../router/app_router.dart';
import '../services/ssh_connection.dart';
import '../services/tmux_startup.dart';

enum TmuxMissingAction { checkAgain, usePlainTerminal, cancelled }

class TmuxMissingDialog {
  static BuildContext _dialogContext(BuildContext context) =>
      rootNavigatorKey.currentContext ?? context;

  static Future<TmuxMissingAction> show(BuildContext context) async {
    final dialogContext = _dialogContext(context);
    return await showDialog<TmuxMissingAction>(
          context: dialogContext,
          barrierDismissible: false,
          useRootNavigator: true,
          builder: (ctx) => AlertDialog(
            title: const Text('tmux not installed'),
            content: const SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'This server does not have tmux. Install it on the server yourself, '
                    'then tap Check again.',
                  ),
                  SizedBox(height: 16),
                  Text('Common install commands:', style: TextStyle(fontWeight: FontWeight.w600)),
                  SizedBox(height: 8),
                  _InstallHint(label: 'Debian / Ubuntu', command: 'sudo apt install tmux'),
                  _InstallHint(label: 'Fedora / RHEL', command: 'sudo dnf install tmux'),
                  _InstallHint(label: 'Alpine', command: 'sudo apk add tmux'),
                  _InstallHint(label: 'macOS', command: 'brew install tmux'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, TmuxMissingAction.cancelled),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, TmuxMissingAction.usePlainTerminal),
                child: const Text('Use plain terminal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, TmuxMissingAction.checkAgain),
                child: const Text('Check again'),
              ),
            ],
          ),
        ) ??
        TmuxMissingAction.cancelled;
  }
}

class _InstallHint extends StatelessWidget {
  const _InstallHint({required this.label, required this.command});

  final String label;
  final String command;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                SelectableText(command, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: command));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Copied: $command')),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Resolves whether to proceed with tmux when the user requested it.
/// Returns null if the user cancelled.
class TmuxAvailability {
  /// Shows the checking dialog without awaiting it — [showDialog] only completes
  /// when the route is popped, so awaiting here would deadlock the tmux check.
  static void _showChecking(BuildContext context) {
    final dialogContext = TmuxMissingDialog._dialogContext(context);
    if (!dialogContext.mounted) return;
    showDialog<void>(
      context: dialogContext,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 16),
            Expanded(child: Text('Checking for tmux on server...')),
          ],
        ),
      ),
    );
  }

  static void _hideChecking(BuildContext context) {
    final dialogContext = TmuxMissingDialog._dialogContext(context);
    if (dialogContext.mounted) {
      Navigator.of(dialogContext, rootNavigator: true).pop();
    }
  }

  static Future<({bool useTmux})?> resolve({
    required BuildContext context,
    required SshConnection connection,
    required bool wantsTmux,
  }) async {
    if (!wantsTmux) return (useTmux: false);

    if (!context.mounted) return null;
    _showChecking(context);

    try {
      final installed = await TmuxStartup.isInstalled(connection);
      if (installed) return (useTmux: true);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not check for tmux: $e')),
        );
      }
      return null;
    } finally {
      _hideChecking(context);
    }

    while (true) {
      if (!context.mounted) return null;
      final action = await TmuxMissingDialog.show(context);
      if (!context.mounted) return null;

      switch (action) {
        case TmuxMissingAction.cancelled:
          return null;
        case TmuxMissingAction.usePlainTerminal:
          return (useTmux: false);
        case TmuxMissingAction.checkAgain:
          _showChecking(context);
          try {
            final installed = await TmuxStartup.isInstalled(connection);
            if (installed) return (useTmux: true);
          } catch (e) {
            if (!context.mounted) return null;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not check for tmux: $e')),
            );
            continue;
          } finally {
            _hideChecking(context);
          }
          if (!context.mounted) return null;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('tmux still not found on the server')),
          );
      }
    }
  }
}
