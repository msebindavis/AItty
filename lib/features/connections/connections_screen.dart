import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/obsidian_colors.dart';
import '../../models/host.dart';
import '../../models/session.dart';
import '../../models/workspace_template.dart';
import '../../providers/hosts_provider.dart';
import '../../services/ssh_connection.dart';
import '../../services/ssh_key_repository.dart';
import '../../services/workspace_manager.dart';
import '../../widgets/tmux_missing_dialog.dart';
import '../../services/workspace_repository.dart';
import '../../utils/open_workspace.dart';
import '../../widgets/connection_session_card.dart';
import '../../widgets/section_header.dart';

Future<({Host host, SshConnection? probe, bool useTmux})?> _probeTmuxForHost(
  BuildContext context,
  WidgetRef ref,
  Host host, {
  required bool wantsTmux,
}) async {
  if (!wantsTmux) return (host: host, probe: null, useTmux: false);

  final probe = await SshConnection.connect(
    host: host,
    hosts: ref.read(hostRepositoryProvider),
    keys: ref.read(sshKeyRepositoryProvider),
    knownHosts: ref.read(knownHostsStoreProvider),
  );
  if (!context.mounted) {
    await probe.disconnect();
    return null;
  }
  final resolved = await TmuxAvailability.resolve(
    context: context,
    connection: probe,
    wantsTmux: true,
  );
  if (!context.mounted) {
    await probe.disconnect();
    return null;
  }
  if (resolved == null) {
    await probe.disconnect();
    return null;
  }
  return (host: host, probe: probe, useTmux: resolved.useTmux);
}

Future<void> _openTemplate(
  BuildContext context,
  WidgetRef ref,
  WorkspaceTemplate template,
  AsyncValue<List<Host>> hostsAsync,
) async {
  try {
    final host = hostsAsync.maybeWhen(
      data: (hosts) {
        for (final h in hosts) {
          if (h.id == template.hostId) return h;
        }
        return null;
      },
      orElse: () => null,
    );
    if (host == null) throw StateError('Host not found');

    final probeResult = await _probeTmuxForHost(context, ref, host, wantsTmux: true);
    if (!context.mounted || probeResult == null) return;

    final ws = await ref.read(workspaceManagerProvider).openTemplate(
          template,
          useTmux: probeResult.useTmux,
          existing: probeResult.probe,
        );
    if (context.mounted) openWorkspace(context, ws.id);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Open template failed: $e')),
      );
    }
  }
}

Future<void> _renameWorkspace(
  BuildContext context,
  WidgetRef ref,
  String workspaceId,
  String currentName,
) async {
  final nameCtrl = TextEditingController(text: currentName);
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Rename workspace'),
      content: TextField(
        controller: nameCtrl,
        decoration: const InputDecoration(labelText: 'Workspace name'),
        autofocus: true,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (name == null || name.isEmpty || !context.mounted) return;
  try {
    await ref.read(workspaceManagerProvider).renameWorkspace(workspaceId, name);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Rename failed: $e')));
    }
  }
}



class ConnectionsScreen extends ConsumerWidget {
  const ConnectionsScreen({super.key});

  static int _sortKey(SessionState state) => switch (state) {
        SessionState.awaitingInput => 0,
        SessionState.reconnecting => 1,
        SessionState.disconnected => 2,
        SessionState.processing => 3,
        SessionState.connected => 4,
        SessionState.idle => 5,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(workspaceManagerProvider);
    final workspaces = [...manager.workspaceSummaries]
      ..sort((a, b) {
        final byState = _sortKey(a.state).compareTo(_sortKey(b.state));
        return byState != 0 ? byState : a.title.compareTo(b.title);
      });
    final templatesAsync = ref.watch(workspaceTemplatesProvider);
    final hostsAsync = ref.watch(hostsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Connections')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showFabMenu(context, ref),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.marginMobile),
        children: [
          const SectionHeader('Open Workspaces'),
          const SizedBox(height: AppSpacing.sm),
          if (workspaces.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: Text(
                'No open workspaces. Tap + to connect.',
                style: AppTypography.inter(size: 14, color: ObsidianColors.onSurfaceVariant),
              ),
            )
          else
            ...workspaces.map(
              (ws) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: ConnectionSessionCard(
                  session: Session(
                    id: ws.id,
                    hostId: ws.hostId,
                    title: ws.title,
                    connectionString: '${ws.terminalCount} terminal${ws.terminalCount == 1 ? '' : 's'}',
                    state: ws.state,
                    lastOutputLine: ws.lastOutputLine,
                  ),
                  onTap: () => openWorkspace(context, ws.id),
                  onLongPress: () => _renameWorkspace(context, ref, ws.id, ws.title),
                  onDisconnect: () => ref.read(workspaceManagerProvider).closeWorkspace(ws.id),
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          templatesAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (templates) {
              if (templates.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeader('Saved Templates'),
                  const SizedBox(height: AppSpacing.sm),
                  ...templates.map(
                    (t) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _TemplateCard(
                        template: t,
                        onTap: () => _openTemplate(context, ref, t, hostsAsync),
                        onDelete: () async {
                          await ref.read(workspaceRepositoryProvider).delete(t.id);
                          ref.invalidate(workspaceTemplatesProvider);
                        },
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  void _showFabMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: ObsidianColors.surfaceContainerHigh,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_link, color: ObsidianColors.primary),
              title: const Text('New Connection'),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/sessions/new/host');
              },
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }
}


class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.onTap,
    required this.onDelete,
  });

  final WorkspaceTemplate template;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ObsidianColors.surface,
      borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
      child: ListTile(
        leading: const Icon(Icons.bookmark_outline, color: ObsidianColors.tertiary),
        title: Text(template.name),
        subtitle: Text('${template.entries.length} terminal(s)'),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: ObsidianColors.outline),
          onPressed: onDelete,
        ),
        onTap: onTap,
      ),
    );
  }
}
